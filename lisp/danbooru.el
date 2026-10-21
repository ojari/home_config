;;; danbooru.el --- Run Anima (run-anima.sh) with Danbooru tags from Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;; Write Danbooru tags as Lisp data, flatten them into one comma separated
;; prompt, run `danbooru-script' asynchronously and show the
;; generated image in an image-mode buffer.
;;
;; M-x danbooru-edit-prompt opens `danbooru-prompt-file' in
;; `danbooru-prompt-mode'.  The file is a sequence of Lisp forms:
;;
;;   ;; subject
;;   (1girl solo
;;    (silver_hair long_hair red_eyes)    ; lists nest freely
;;    $POSE)
;;   (cherry_blossoms night "moonlight through the petals")
;;
;;   (:vary $POSE standing (sitting seiza) "looking back")
;;   (:model aesthetic)
;;
;; Tags are plain words without quotes; nested lists are flattened into a
;; single list and duplicates dropped.  Symbol tags become lowercase;
;; underscores become spaces
;; (silver_hair -> "silver hair"), except in score_N tags.  "Strings" are
;; passed as is, for natural language or tags containing odd characters.
;; Stray commas, as in (red_eyes, kimono), are ignored.
;;
;; C-c C-c flattens the file and generates, C-c C-r does it again with a
;; new seed, C-c C-p shows (and copies) the flat prompt, C-c C-k cancels,
;; C-c C-s toggles the server.
;; Select complete alternatives inside one grouped :vary to preview or
;; generate only those alternatives.  Other variation axes still combine.
;;
;; Directives (top-level lists starting with a keyword):
;;   (:vary $X V1 V2 ...)  one image per value, $X replaced in tags and in
;;                         strings; a value may be a tag, a list of tags or
;;                         a string.  Several :vary give every combination.
;;   (:neg TAGS...)        negative prompt (only used when CFG > 1)
;;   (:caption "...")     natural-language sentences appended after tags
;;   (:artist NAME...)    artist tags with Anima's required @ prefix
;;   (:model aesthetic)    turbo (default) or aesthetic
;;   (:size W H) (:steps N) (:cfg X) (:seed N)
;;   (:def NAME TREE)     define reusable tag data without emitting it
;;   (:include "FILE")    import definitions relative to this file
;; Bare symbols matching a definition expand in tags and :vary values;
;; other symbols and all strings retain their usual meaning.
;;
;; Variations in one batch share one seed.  Each image has a JSON sidecar
;; recording the source, resolved prompt, parameters and actual seed.
;; C-c C-j opens Imenu for :def names; M-n / M-p move between definitions.
;;
;; Server: with `danbooru-server' set (e.g. "http://127.0.0.1:1234" or
;; another machine), prompts are POSTed to sd-server's /sdapi/v1/txt2img
;; with curl instead of starting sd-cli each time, so the model stays
;; loaded.  M-x danbooru-start-server runs "run-anima.sh server" locally
;; (MODEL from `danbooru-model') and points `danbooru-server' at it; on
;; another machine run "HOST=0.0.0.0 ./run-anima.sh server".  The server
;; has one model loaded, so :model is ignored there.  M-x
;; danbooru-toggle-server switches between server and script.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'crm)
(require 'url-parse)
(require 'lisp-mode)
(require 'imenu)

;;; ── Settings ──

(defgroup danbooru nil
  "Anima image generation from Danbooru tags."
  :group 'multimedia)

(defcustom danbooru-script "~/work/ai/run-anima.sh"
  "Script that generates the image."
  :type 'file)

(defcustom danbooru-output-dir "~/work/ai/out/"
  "Base directory for generated images.
File-backed prompts use a subdirectory named after the file without its
extension, for example models2.danbooru saves images under models2/."
  :type 'directory)

(defcustom danbooru-prompt-file "~/work/ai/anima-prompt.danbooru"
  "Prompt file edited by `danbooru-edit-prompt'."
  :type 'file)

(defcustom danbooru-server "http://10.2.2.34:1234"
  "URL of an sd-server running Anima, or nil to run `danbooru-script'.
For example \"http://127.0.0.1:1234\" or \"http://other-host:1234\"."
  :type '(choice (const :tag "Run script" nil) string))

(defcustom danbooru-local-server "http://127.0.0.1:1234"
  "URL used by `danbooru-start-server' and `danbooru-toggle-server'."
  :type 'string)

(defcustom danbooru-model "turbo"
  "Anima model, \"turbo\" or \"aesthetic\"."
  :type '(choice (const "turbo") (const "aesthetic")))

(defcustom danbooru-width 1200 "Image width." :type 'integer)
(defcustom danbooru-height 1200 "Image height." :type 'integer)
(defcustom danbooru-steps nil "Sampling steps, nil for the model default."
  :type '(choice (const nil) integer))
(defcustom danbooru-cfg nil "CFG scale, nil for the model default."
  :type '(choice (const nil) number))
(defcustom danbooru-seed -1 "Seed, -1 for random." :type 'integer)

(defcustom danbooru-underscore-to-space t
  "Non-nil to write tag underscores as spaces (score_N tags excepted)."
  :type 'boolean)

(defcustom danbooru-lowercase-tags t
  "Non-nil to lowercase symbol tags for Anima.
Quoted strings keep their capitalization.  Variation markers keep their
case so that $POSE and $pose remain distinct."
  :type 'boolean)

(defcustom danbooru-tag-file "/home/jari/work/danbooru/tags/vocab/danbooru.csv"
  "CSV file containing Danbooru tags.
The first column is used as the completion candidate; the other columns
contain tag type, usage count and aliases."
  :type 'file)

(defvar danbooru-last-source nil "Prompt text of the last run.")
(defvar danbooru-history nil "History for `danbooru'.")
(defvar danbooru--process nil)
(defvar danbooru--queue nil "Pending generations, plists of :prompt :env :seed :out :label.")
(defvar danbooru--batch nil "Output files of the current batch.")
(defvar danbooru--batch-size 0 "Number of images in the current batch.")
(defvar danbooru--tag-completion-cache nil)
(defvar danbooru--tag-completion-file-mtime nil)

(defun danbooru--tag-completion-table ()
  "Return the cached canonical tags read from `danbooru-tag-file'."
  (let* ((file (expand-file-name danbooru-tag-file))
         (mtime (and (file-readable-p file)
                     (file-attribute-modification-time (file-attributes file)))))
    (unless (and mtime
                 danbooru--tag-completion-cache
                 (equal mtime danbooru--tag-completion-file-mtime))
      (setq danbooru--tag-completion-cache nil
            danbooru--tag-completion-file-mtime mtime)
      (when mtime
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward "^\\([^,\\n]+\\)," nil t)
            (push (match-string-no-properties 1) danbooru--tag-completion-cache)))
        (setq danbooru--tag-completion-cache
              (sort (delete-dups danbooru--tag-completion-cache) #'string<))))
    (or danbooru--tag-completion-cache
        (user-error "danbooru: cannot read tag file %s" file))))

(defun danbooru-complete-tag ()
  "Complete the Danbooru tag at point.
Invoke repeatedly to insert multiple tags in a prompt list."
  (interactive)
  (completion-at-point))

(defun danbooru--completion-at-point ()
  "Provide Danbooru tag completion for the current prompt buffer."
  (unless (or (nth 3 (syntax-ppss)) (nth 4 (syntax-ppss)))
    (let ((end (point)))
      (save-excursion
        (skip-chars-backward "[:alnum:]_:/?+*!@%=-")
        (let ((start (point)))
          (list start end (append (danbooru--library-block-names)
                                 (danbooru--tag-completion-table))
                :exclusive 'no))))))

(defun danbooru--library-block-names ()
  "Return local and imported block names from complete top-level forms.
Tolerate an unfinished form at point.
Broken libraries are reported by preview and generation, not completion."
  (let (forms)
    (with-syntax-table emacs-lisp-mode-syntax-table
      (save-excursion
        (goto-char (point-min))
        (condition-case nil
            (while (progn (forward-comment (point-max)) (not (eobp)))
              (push (read (current-buffer)) forms))
          ((end-of-file invalid-read-syntax) nil))))
    (condition-case nil
        (let ((collected (danbooru--include-forms
                          (nreverse forms)
                          (or (and buffer-file-name (file-name-directory buffer-file-name))
                              default-directory)
                          (and buffer-file-name (list (file-truename buffer-file-name)))
                          (make-hash-table :test #'equal))))
          (cl-loop for form in collected
                   when (and (consp form) (eq (car form) :def)
                             (symbolp (cadr form)) (cadr form))
                   collect (symbol-name (cadr form))))
      (user-error nil))))

;;; ── Parsing ──

(defconst danbooru--directives
  '(:vary :neg :caption :artist :model :size :steps :cfg :seed)
  "Directive keywords recognized after block and include expansion.")

(defun danbooru--read-forms (text)
  "Return the list of Lisp forms in TEXT."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (let (forms)
      (while (progn (forward-comment (point-max)) (not (eobp)))
        (when (memq (char-after) '(?\{ ?\[))
          (user-error "danbooru: prompts must use Lisp forms"))
        (let ((line (line-number-at-pos)))
          (condition-case err
              (push (read (current-buffer)) forms)
            (end-of-file
             (user-error "danbooru: incomplete form at line %d" line))
            (error
             (user-error "danbooru: syntax error at line %d: %s"
                         line (error-message-string err))))))
      (nreverse forms))))

(defun danbooru--include-forms (forms directory stack seen &optional library)
  "Collect FORMS and included block definitions relative to DIRECTORY.
STACK detects recursive includes; SEEN makes repeated includes idempotent.
When LIBRARY is non-nil, allow only :def and :include forms."
  (cl-loop
   for form in forms append
   (cond
    ((and (consp form) (eq (car form) :include))
     (unless (and (proper-list-p form) (= (length form) 2)
                  (stringp (cadr form)) (not (string-empty-p (cadr form))))
       (user-error "danbooru: :include requires one nonempty file name string"))
     (let ((file (file-truename (expand-file-name (cadr form) directory))))
       (when (member file stack)
         (user-error "danbooru: circular library include: %s"
                     (string-join (reverse (cons file stack)) " -> ")))
       (unless (gethash file seen)
         (puthash file t seen)
         (let ((included
                (condition-case err
                    (with-temp-buffer
                      (insert-file-contents file)
                      (danbooru--read-forms (buffer-string)))
                  ((file-error user-error)
                   (user-error "danbooru: library %s: %s" file
                               (error-message-string err))))))
           (danbooru--include-forms included (file-name-directory file)
                                    (cons file stack) seen t)))))
    ((and library (not (and (consp form) (eq (car form) :def))))
     (user-error "danbooru: library %s may contain only :def and :include forms"
                 (car stack)))
    (t (list form)))))

(defun danbooru--resolve-block-tree (tree blocks cache &optional resolving)
  "Expand defined symbols in tag TREE using BLOCKS.
Memoize expansions in CACHE; strings and undefined symbols remain literal.
RESOLVING holds the block names being expanded, for cycle detection."
  (cond
   ((and (symbolp tree) (assq tree blocks))
    (let ((name tree)
          (block (assq tree blocks)))
      (when (memq name resolving)
        (user-error "danbooru: circular block reference: %s"
                    (mapconcat #'symbol-name (reverse (cons name resolving)) " -> ")))
      (let ((cached (gethash name cache cache)))
        (if (eq cached cache)
            (puthash name (danbooru--resolve-block-tree
                           (cdr block) blocks cache (cons name resolving)) cache)
          cached))))
   ((consp tree)
    (when (memq (car tree) '(:def :include))
      (user-error "danbooru: %s is only allowed at top level" (car tree)))
    (when (and (keywordp (car tree)) (not (eq (car tree) :artist)))
      (user-error "danbooru: unknown tag directive %s" (car tree)))
    (if (proper-list-p tree)
        (mapcar (lambda (item) (danbooru--resolve-block-tree item blocks cache resolving))
                tree)
      (cons (danbooru--resolve-block-tree (car tree) blocks cache resolving)
            (danbooru--resolve-block-tree (cdr tree) blocks cache resolving))))
   ((vectorp tree)
    (apply #'vector (mapcar (lambda (item)
                             (danbooru--resolve-block-tree item blocks cache resolving))
                           tree)))
   (t tree)))

(defun danbooru--resolve-library-form (form blocks cache)
  "Expand tag data in prompt FORM using BLOCKS and CACHE."
  (if (not (and (consp form) (memq (car form) danbooru--directives)
                (proper-list-p form)))
      (danbooru--resolve-block-tree form blocks cache)
    (pcase (car form)
      (:vary
       (append (cl-subseq form 0 (min 2 (length form)))
               (danbooru--resolve-block-tree (cddr form) blocks cache)))
      ((or :neg :artist)
       (cons (car form) (danbooru--resolve-block-tree (cdr form) blocks cache)))
      (_ form))))

(defun danbooru--library-forms (forms &optional directory)
  "Return FORMS with includes collected and named blocks expanded.
DIRECTORY defaults to the prompt file's directory or `default-directory'.
Block definitions are data, support forward references, and emit no tags."
  (let* ((directory (or directory (and buffer-file-name
                                      (file-name-directory buffer-file-name))
                        default-directory))
         (forms (danbooru--include-forms
                 forms directory (and buffer-file-name
                                      (list (file-truename buffer-file-name)))
                 (make-hash-table :test #'equal)))
         (cache (make-hash-table :test #'eq))
         blocks prompt)
    (dolist (form forms)
      (if (and (consp form) (eq (car form) :def))
          (progn
            (unless (and (proper-list-p form) (= (length form) 3)
                         (cadr form) (symbolp (cadr form))
                         (not (keywordp (cadr form))))
              (user-error "danbooru: %s requires a symbolic name and one tag tree" (car form)))
            (when (assq (cadr form) blocks)
              (user-error "danbooru: duplicate block %s" (cadr form)))
            (danbooru--validate-tags (caddr form) (format "block %s" (cadr form)))
            (push (cons (cadr form) (caddr form)) blocks))
        (push form prompt)))
    ;; Check unused definitions too, so broken libraries fail predictably.
    (dolist (block blocks)
      (danbooru--resolve-block-tree (car block) blocks cache))
    (mapcar (lambda (form) (danbooru--resolve-library-form form blocks cache))
            (nreverse prompt))))

(defun danbooru--parse (text &optional directory)
  "Parse Lisp prompt TEXT into a plist.
Keys are :tags (list of tag trees), :caption (list of strings), :vary
(alist of MARKER and value trees), :neg
(tag tree), :source (self-contained source), and generation options.
DIRECTORY is the base directory for includes, when supplied."
  (let* ((original (danbooru--read-forms text))
         (forms (danbooru--library-forms original directory))
         (source (if (equal original forms) text
                   (let ((print-length nil) (print-level nil))
                     (mapconcat #'prin1-to-string forms "\n"))))
         tags vary result)
    (dolist (form forms)
      (when (and (consp form) (keywordp (car form))
                 (not (memq (car form) danbooru--directives)))
        (user-error "danbooru: unknown directive %s" (car form)))
      (if (and (consp form) (memq (car form) danbooru--directives))
          (progn
            (unless (proper-list-p form)
              (user-error "danbooru: directive %s must be a proper list" (car form)))
            (when (and (memq (car form) '(:model :steps :cfg :seed))
                       (/= (length form) 2))
              (user-error "danbooru: %s requires one value" (car form)))
            (pcase (car form)
              (:vary (let ((marker (format "%s" (cadr form))))
                       (unless (and (cadr form)
                                    (or (stringp (cadr form)) (symbolp (cadr form)))
                                    (not (keywordp (cadr form)))
                                    (not (string-empty-p marker)))
			 (user-error "danbooru: invalid variation marker %S" (cadr form)))
                       (when (assoc marker vary)
			 (user-error "danbooru: duplicate variation %s" marker))
                       (unless (cddr form)
			 (user-error "danbooru: (:vary %s) has no values" marker))
                       (push (cons marker (cddr form)) vary)))
              (:artist
               (unless (cdr form) (user-error "danbooru: :artist needs a name"))
               (danbooru--validate-tags (cdr form) "artist")
               (push form tags))
              (:caption
               (unless (and (= (length form) 2) (stringp (cadr form)))
                 (user-error "danbooru: :caption requires one string"))
               (setq result (plist-put result :caption
                                       (append (plist-get result :caption) (cdr form)))))
              (:neg (setq result (plist-put result :neg
                                            (append (plist-get result :neg) (cdr form)))))
              (:model (setq result (plist-put result :model (format "%s" (cadr form)))))
              (:size (setq result (plist-put result :size (cdr form))))
              (key (setq result (plist-put result key (cadr form))))))
        (push form tags)))
    (append (list :source source :tags (nreverse tags) :vary (nreverse vary)) result)))

;;; ── Flattening ──

(defun danbooru--tag-name (name)
  "Return tag NAME as written in the prompt."
  (when (and danbooru-lowercase-tags (not (string-prefix-p "$" name)))
    (setq name (downcase name)))
  (if (and danbooru-underscore-to-space
           (not (string-prefix-p "score_" name))
           (not (string-prefix-p "$" name)))
      (string-replace "_" " " name)
    name))

(defun danbooru--flatten (tree &optional subst resolving)
  "Return the tags of TREE as a flat list of strings.
SUBST is an alist of (MARKER . VALUE-TREE): a symbol MARKER is replaced
by the tags of VALUE-TREE and MARKER inside strings by them joined.
A tree (:artist NAMES...) renders normalized, @-prefixed artist tags."
  (cond ((null tree) nil)
        ((and (consp tree) (eq (car tree) :artist))
         ;; The explicit artist context also normalizes quoted names.  Other
         ;; strings, especially captions and weighted tags, stay untouched.
         (mapcar (lambda (name)
                   (if (string-match-p "\\$[[:alnum:]_-]+" name) name
                     (concat "@" (downcase
                                  (string-replace "_" " "
                                                  (string-remove-prefix "@" name))))))
                 (danbooru--flatten (cdr tree) subst resolving)))
        ((and (consp tree) (memq (car tree) '(\, \,@ quote \`)))
         (danbooru--flatten (cdr tree) subst resolving))
        ((consp tree)
         (append (danbooru--flatten (car tree) subst resolving)
                 (danbooru--flatten (cdr tree) subst resolving)))
        ((vectorp tree) (danbooru--flatten (append tree nil) subst resolving))
        ((symbolp tree)
         (let ((v (assoc (symbol-name tree) subst)))
           (if v
               (progn
                 (when (member (car v) resolving)
                   (user-error "danbooru: cyclic placeholder %s" (car v)))
                 (danbooru--flatten (cdr v) subst (cons (car v) resolving)))
             (list (danbooru--tag-name (symbol-name tree))))))
        ((stringp tree)
         (when subst
           (setq tree
                 (replace-regexp-in-string
                  (concat (regexp-opt (mapcar #'car subst)) "[[:alnum:]_-]*")
                  (lambda (marker)
                    (let ((entry (assoc marker subst)))
                      (if (null entry) marker
                        (when (member marker resolving)
                          (user-error "danbooru: cyclic placeholder %s" marker))
                        (danbooru--join
                         (danbooru--flatten (cdr entry) subst (cons marker resolving))))))
                  tree t t)))
         (let ((s (string-trim tree)))
           (unless (string-empty-p s) (list s))))
        (t (list (format "%s" tree)))))

(defun danbooru--join (tags)
  "Return TAGS without duplicates joined with commas."
  (string-join (delete-dups (copy-sequence tags)) ", "))

(defun danbooru--sentence (text)
  "Trim TEXT and finish it with punctuation unless it already has some."
  (let ((text (string-trim text)))
    (if (or (string-empty-p text)
            (string-match-p "[.!?][\"'”’)]*\\'" text))
        text
      (concat text "."))))

(defun danbooru--captions (tree combo)
  "Render caption TREE as sentences, resolving variation COMBO.
Keep captions separate from the comma-separated tags and from each other."
  (mapcar #'danbooru--sentence
          (delete-dups (danbooru--flatten tree combo))))

(defun danbooru--expand-prompt (p)
  "Expand parsed prompt P into jobs, one per :vary combination.
Each job is a plist of :label, :prompt, :seed and :params, a plist of
:model, :width, :height, :steps, :cfg and :neg (nil means default)."
  (let* ((tags (plist-get p :tags))
         (neg (plist-get p :neg))
         (all (prin1-to-string (list tags neg (plist-get p :caption)
                                    (mapcar #'cdr (plist-get p :vary)))))
         (combos (list nil))
         (size (plist-get p :size)))
    (pcase-dolist (`(,marker . ,vals) (plist-get p :vary))
      (unless (string-search marker all)
        (user-error "danbooru: placeholder %s does not occur in the prompt" marker))
      (setq combos (cl-loop for c in combos
                            append (cl-loop for v in vals
                                            collect (append c (list (cons marker v)))))))
    (mapcar (lambda (combo)
              (let* ((tag-text (danbooru--join (danbooru--flatten tags combo)))
                     (captions (danbooru--captions (plist-get p :caption) combo))
                     (prompt (string-join
                              (append (unless (string-empty-p tag-text) (list tag-text))
                                      captions)
                              "\n")))
                (when (string-empty-p prompt)
                  (user-error "danbooru: no tags or caption"))
                (list :label (and combo
                                  (mapconcat (lambda (c) (danbooru--join (danbooru--flatten (cdr c))))
                                             combo " / "))
                      :prompt prompt
                      :seed (plist-get p :seed)
                      :params (list :model (or (plist-get p :model) danbooru-model)
                                    :width (or (car size) danbooru-width)
                                    :height (or (cadr size) danbooru-height)
                                    :steps (or (plist-get p :steps) danbooru-steps)
                                    :cfg (or (plist-get p :cfg) danbooru-cfg)
                                    :neg (and neg (danbooru--join (danbooru--flatten neg combo)))))))
            combos)))

;;; ── Validation ──

(defconst danbooru--parameter-keys '(:model :size :steps :cfg :seed))

(defun danbooru--validate-tags (tree context)
  "Check that TREE contains only declarative tags in CONTEXT."
  (cond ((null tree))
        ((or (stringp tree) (numberp tree)))
        ((and (symbolp tree) (not (keywordp tree))))
        ((and (consp tree) (proper-list-p tree) (eq (car tree) :artist)
              (cdr tree))
         (danbooru--validate-tags (cdr tree) context))
        ((and (consp tree) (proper-list-p tree))
         (mapc (lambda (v) (danbooru--validate-tags v context)) tree))
        (t (user-error "danbooru: invalid tag data %S in %s" tree context))))

(defun danbooru--validate-parameters (props context)
  "Validate supplied generation parameters in PROPS for CONTEXT."
  (dolist (key danbooru--parameter-keys)
    (when (plist-member props key)
      (let ((value (plist-get props key)))
        (unless
            (pcase key
              (:model (member (format "%s" value) '("turbo" "aesthetic")))
              (:size (and (proper-list-p value) (= (length value) 2)
                          (cl-every (lambda (n) (and (integerp n) (> n 0))) value)))
              (:steps (or (null value) (and (integerp value) (> value 0))))
              (:cfg (or (null value) (and (numberp value) (>= value 0))))
              (:seed (and (integerp value) (>= value -1))))
          (user-error "danbooru: invalid %s %S in %s" key value context))))))

(defun danbooru--expand (text &optional directory)
  "Compile Lisp prompt TEXT into one job per variation combination.
DIRECTORY, when supplied, is the base directory for includes.
Jobs carry a self-contained :source snapshot for regeneration without
library dependencies."
  (let* ((p (danbooru--parse text directory))
         (_ (danbooru--validate-parameters p "prompt"))
         (jobs (danbooru--expand-prompt p)))
    (mapcar (lambda (job) (plist-put job :source (plist-get p :source))) jobs)))

;;; ── Running ──

(defun danbooru--slug (s)
  "Return S as a short file-name-safe string."
  (let ((slug (string-trim (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase s))
                           "-+" "-+")))
    (substring slug 0 (min 40 (length slug)))))

(defun danbooru--output-file (stamp &optional index label)
  "Return output file name for timestamp STAMP.
For batches INDEX and LABEL are added to STAMP.
Use the current prompt file's basename as a subdirectory when available."
  (let ((dir (if buffer-file-name
                 (expand-file-name (file-name-base buffer-file-name)
                                   danbooru-output-dir)
               (expand-file-name danbooru-output-dir))))
    (make-directory dir t)
    (expand-file-name (if index
                          (format "%s-%s.png" stamp (danbooru--slug label))
                        (format "%s.png" stamp))
                      dir)))

(defun danbooru-generate (text &optional seed)
  "Generate images from prompt TEXT asynchronously.
TEXT is in the prompt file format, see the commentary; a plain comma
separated tag string also works.  One image is made per :vary
combination.  SEED overrides the file seed.  Random seeds are shared by
all variants in this batch and saved alongside each image.  If a
generation is running, the new images are queued after it."
  (when seed (danbooru--validate-parameters (list :seed seed) "seed override"))
  (danbooru--enqueue-jobs (danbooru--expand text) text seed))

(defun danbooru--enqueue-jobs (jobs text &optional seed)
  "Queue compiled JOBS with source TEXT and optional overriding SEED."
  (let* ((text (or (plist-get (car jobs) :source) text))
         (requested (or seed (plist-get (car jobs) :seed) danbooru-seed))
         (actual (if (>= requested 0) requested (random 2147483647)))
         (stamp (format-time-string "%m%d-%H%M"))
         (batch (cdr jobs))
         (index 0))
    (setq danbooru-last-source text)
    (unless (process-live-p danbooru--process)
      (setq danbooru--batch nil
            danbooru--batch-size 0)
      (with-current-buffer (get-buffer-create "*danbooru-log*")
        (erase-buffer)))
    (dolist (job jobs)
      (let ((label (plist-get job :label)))
        (setq danbooru--queue
              (append danbooru--queue
                      (list (list :prompt (plist-get job :prompt) :params (plist-get job :params)
                                  :seed actual :label label :source text
                                  :server danbooru-server
                                  :out (danbooru--output-file
                                        stamp (and batch (cl-incf index)) label)))))))
    (cl-incf danbooru--batch-size (length jobs))
    (if (process-live-p danbooru--process)
        (message "danbooru: queued %d image(s)" (length jobs))
      (danbooru--start-next))))

(defun danbooru--script-process (prompt params seed out log)
  "Start `danbooru-script' for PROMPT, PARAMS and SEED writing OUT.
Output goes to buffer LOG."
  (let ((process-environment
         (append (list (format "OUT=%s" out)
                       (format "SEED=%d" seed))
                 (cl-loop for (key var) on '(:model "MODEL" :width "W" :height "H"
						    :steps "STEPS" :cfg "CFG" :neg "NEG")
                          by #'cddr
                          for v = (plist-get params key)
                          when v collect (format "%s=%s" var v))
                 process-environment)))
    (make-process
     :name "danbooru"
     :buffer log
     :command (list (expand-file-name danbooru-script) prompt))))

(defun danbooru--server-process (prompt params seed out log &optional server)
  "POST PROMPT, PARAMS and SEED to `danbooru-server', saving the image as OUT.
curl runs asynchronously; the response is decoded by
`danbooru--save-response' and errors go to buffer LOG."
  (let* ((resp (with-current-buffer (get-buffer-create " *danbooru-response*")
                 (erase-buffer)
                 (current-buffer)))
         (body (json-serialize
                (danbooru--obj
                 (list :prompt prompt
                       :negative_prompt (plist-get params :neg)
                       :width (plist-get params :width)
                       :height (plist-get params :height)
                       :steps (plist-get params :steps)
                       :cfg_scale (plist-get params :cfg)
                       :seed seed
                       :sampler_name "euler"))))
         (proc (make-process
                :name "danbooru"
                :buffer resp
                :stderr log
                :coding 'utf-8
                :connection-type 'pipe
                :command (list "curl" "-sS" "--fail-with-body"
                               "-H" "Content-Type: application/json"
                               "--data-binary" "@-"
                               (concat (string-remove-suffix "/" (or server danbooru-server))
                                       "/sdapi/v1/txt2img")))))
    (process-put proc 'danbooru-out out)
    (process-send-string proc body)
    (process-send-eof proc)
    proc))

(defun danbooru--obj (plist)
  "Return PLIST with nil values dropped."
  (cl-loop for (k v) on plist by #'cddr when v append (list k v)))

(defun danbooru--save-response (proc log)
  "Write the image in the txt2img response of PROC to its output file.
Return non-nil on success, else copy the response to buffer LOG."
  (let ((out (process-get proc 'danbooru-out))
        (resp (process-buffer proc)))
    (condition-case err
        (let* ((data (with-current-buffer resp
                       (goto-char (point-min))
                       (json-parse-buffer :object-type 'plist :array-type 'list)))
               (image (car (plist-get data :images))))
          (unless image (error "no image in response"))
          (let ((coding-system-for-write 'binary))
            (write-region (base64-decode-string image) nil out nil 'silent))
          t)
      (error
       (with-current-buffer log
         (goto-char (point-max))
         (insert (format "server error: %s\n" (error-message-string err))
                 (with-current-buffer resp
                   (buffer-substring (point-min) (min (point-max) 500)))
                 "\n"))
       nil))))

(defun danbooru--start-next ()
  "Start the next queued generation, or finish the batch."
  (if (null danbooru--queue)
      (when (cdr danbooru--batch)
        (message "danbooru: batch done, %d images" (length danbooru--batch))
        (dired (cons (expand-file-name danbooru-output-dir) (reverse danbooru--batch))))
    (cl-destructuring-bind (&key prompt params seed out label source server)
        (pop danbooru--queue)
      (let ((log (get-buffer-create "*danbooru-log*"))
            (n (- danbooru--batch-size (length danbooru--queue))))
        (with-current-buffer log
          (goto-char (point-max))
          (insert (format "== %s seed %d%s%s\n%S\n%s\n\n"
                          (file-name-nondirectory out) seed
                          (if label (format " [%s]" label) "")
                          (if server (format " via %s" server) "")
                          params prompt)))
        (setq danbooru--process
              (if server
                  (danbooru--server-process prompt params seed out log server)
                (danbooru--script-process prompt params seed out log)))
        (set-process-sentinel
         danbooru--process
         (lambda (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (if (and (zerop (process-exit-status proc))
                      (or (not server) (danbooru--save-response proc log))
                      (file-exists-p out))
                 (progn (message "danbooru: done %s" out)
                        (cl-pushnew out danbooru--batch :test #'equal)
                        (condition-case err
                            (danbooru--save-metadata out source prompt params seed server)
                          (error (with-current-buffer log
                                   (goto-char (point-max))
                                   (insert (format "metadata error: %s\n"
                                                   (error-message-string err))))))
                        (danbooru-show out source)
                        (danbooru--start-next))
               (when (and server
                          (not (zerop (process-exit-status proc)))
                          (> (buffer-size (process-buffer proc)) 0))
                 (danbooru--save-response proc log))
               (setq danbooru--queue nil)
               (message "danbooru: failed (see *danbooru-log*)")
               (display-buffer log)))))
        (message "danbooru: generating %d/%d %s..." n danbooru--batch-size
                 (if label (format "\"%s\"" label) (file-name-nondirectory out)))))))

(defun danbooru-cancel ()
  "Stop the running generation and drop the queued ones.
With `danbooru-server' only the request is dropped, the server still
finishes the image it is working on."
  (interactive)
  (setq danbooru--queue nil)
  (when (process-live-p danbooru--process)
    (delete-process danbooru--process))
  (message "danbooru: cancelled"))

;;; ── Server ──

(defun danbooru-start-server ()
  "Run \"`danbooru-script' server\" and send prompts to it.
The model is `danbooru-model'; the server listens on the port of
`danbooru-local-server'."
  (interactive)
  (let* ((url (url-generic-parse-url danbooru-local-server))
         (process-environment
          (append (list (format "MODEL=%s" danbooru-model)
                        (format "PORT=%s" (url-port url)))
                  process-environment)))
    (unless (process-live-p (get-buffer-process "*danbooru-server*"))
      (make-process :name "danbooru-server"
                    :buffer (get-buffer-create "*danbooru-server*")
                    :command (list (expand-file-name danbooru-script) "server")))
    (setq danbooru-server danbooru-local-server)
    (message "danbooru: server %s (%s), see *danbooru-server*" danbooru-server danbooru-model)))

(defun danbooru-stop-server ()
  "Stop the server started by `danbooru-start-server' and use the script."
  (interactive)
  (when-let ((proc (get-buffer-process "*danbooru-server*")))
    (delete-process proc))
  (setq danbooru-server nil)
  (message "danbooru: server stopped, using %s" danbooru-script))

(defun danbooru-toggle-server (&optional url)
  "Switch between `danbooru-script' and the sd-server at URL.
With a prefix argument ask for the URL."
  (interactive
   (list (and current-prefix-arg
              (read-string "Server URL: " (or danbooru-server danbooru-local-server)))))
  (setq danbooru-server (if (or url (null danbooru-server))
                            (or url danbooru-local-server)
                          nil))
  (message "danbooru: using %s" (or danbooru-server danbooru-script)))

;;; ── Display ──

(defvar-local danbooru-source nil "Prompt text that produced this image.")

(defun danbooru--save-metadata (out source prompt params seed server)
  "Save the inputs that produced OUT to a neighboring JSON file."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file (concat out ".json")
      (insert (json-serialize
               (list :version 1 :source source
                     :prompt prompt :seed seed
                     :requested_parameters (danbooru--obj params)
                     :backend (or server (expand-file-name danbooru-script)))))
      (insert "\n"))))

(defun danbooru-show (file &optional source)
  "Show image FILE in image-mode, remembering SOURCE as its prompt."
  (let* ((existing (get-file-buffer file))
         (buf (or existing (find-file-noselect file))))
    (with-current-buffer buf
      (when existing (revert-buffer t t))
      (setq danbooru-source source))
    (display-buffer buf)))

;;; ── Commands ──

(defun danbooru (tags)
  "Generate an image from TAGS, a comma separated string."
  (interactive
   (list (string-join (completing-read-multiple
                       "Tags (comma separated): "
                       (danbooru--tag-completion-table)
                       nil nil nil 'danbooru-history)
                      ", ")))
  (danbooru-generate (prin1-to-string (string-trim tags))))

(defun danbooru-regenerate ()
  "Run the last prompt (or this image's prompt) again with a random seed."
  (interactive)
  (let ((text (or danbooru-source danbooru-last-source)))
    (unless text (user-error "danbooru: no previous prompt"))
    (danbooru-generate text -1)))

;;; ── Prompt file ──

(defvar danbooru-default-prompt
  ";;; Anima prompt  -*- mode: danbooru-prompt -*-
;; C-c C-c generate   C-c C-r new seed   C-c C-p show flat prompt   C-c C-k cancel
;; C-c C-s toggle sd-server (M-x danbooru-start-server to run one locally)
;; Select complete alternatives inside :vary to preview/generate only those.
;; Tags are words without quotes, lists nest and are flattened into one list.
;; SILVER_HAIR -> \"silver hair\"; \"strings\" keep spelling and capitalization.
;; Use tags for appearance; use :caption for actions and relationships.

;; Optional quality/style cues; no score_* needed for Aesthetic.
(masterpiece best_quality safe)

;; Count, character, series, then artist (if wanted), then general tags.
;; (:artist some_artist)         ; emits @some artist; also works inside tag lists
(1girl solo
 (silver_hair long_hair red_eyes)
 (kimono obi))

;; Scene tags and a natural-language caption complement each other.
(cherry_blossoms night outdoors)
(:caption \"An adult woman in a kimono is $POSE beneath the cherry blossoms. Moonlight shines through the petals and lights her silver hair.\")

(:vary $POSE \"standing beside a tree\" \"sitting in seiza\" \"looking back over her shoulder\")
;; Turbo is designed for CFG 1 and 8-12 steps; keep backend defaults.
;; (:model aesthetic)            ; script mode only; server keeps its loaded model
;; (:size 832 1216)
;; (:neg blurry jpeg_artifacts)  ; only effective when CFG > 1
"
  "Text written to `danbooru-prompt-file' when it does not exist yet.")

(defun danbooru--selected-vary-text (begin end)
  "Return prompt text restricted to the alternatives between BEGIN and END.
The region must contain complete alternatives inside one top-level :vary.
Keep the surrounding prompt and other variation axes, without editing the
buffer.  The returned source records just the selected alternatives so
regenerating an image uses the same subset."
  (with-syntax-table emacs-lisp-mode-syntax-table
    (save-excursion
      (goto-char (point-min))
      (catch 'selected
        (condition-case err
            (while (progn (forward-comment (point-max)) (not (eobp)))
              (let* ((start (point))
                     (form (read (current-buffer)))
                     (finish (point)))
                (when (and (< start end) (< begin finish))
                  (unless (and (proper-list-p form) (eq (car form) :vary)
                               (cddr form))
                    (user-error "danbooru: select alternatives inside one top-level :vary"))
                  (goto-char (1+ start))
                  (read (current-buffer)) ; :vary
                  (read (current-buffer)) ; marker
                  (let ((values-start (point))
                        (values-end (1- finish))
                        selected)
                    (unless (and (<= values-start begin) (<= end values-end))
                      (user-error "danbooru: select only alternatives, without the :vary header or closing parenthesis"))
                    (dolist (_ (cddr form))
                      (forward-comment (point-max))
                      (let ((value-start (point)))
                        (read (current-buffer))
                        (when (and (< begin (point)) (< value-start end))
                          (unless (and (<= begin value-start) (<= (point) end))
                            (user-error "danbooru: select complete :vary alternatives"))
                          (push (buffer-substring-no-properties value-start (point))
                                selected))))
                    (unless selected
                      (user-error "danbooru: selection contains no :vary alternatives"))
                    (throw 'selected
                           (concat (buffer-substring-no-properties (point-min) values-start)
                                   "\n" (string-join (nreverse selected) "\n") "\n"
                                   (buffer-substring-no-properties values-end (point-max))))))))
          ((end-of-file invalid-read-syntax)
           (user-error "danbooru: invalid prompt: %s" (error-message-string err))))
        (user-error "danbooru: select alternatives inside one top-level :vary")))))

(defun danbooru--buffer-text (&optional selected)
  "Return the prompt text of the current buffer.
When SELECTED is non-nil and the region is active, restrict one top-level
:vary to its selected complete alternatives."
  (if (and selected (use-region-p))
      (danbooru--selected-vary-text (region-beginning) (region-end))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun danbooru-prompt-generate (&optional seed)
  "Save the prompt buffer, flatten its tags and generate the image(s).
An active region selects complete alternatives inside one grouped :vary;
the rest of the prompt and other variation axes remain active."
  (interactive)
  (let ((text (danbooru--buffer-text t)))
    (when buffer-file-name (save-buffer))
    (danbooru-generate text seed)))

(defun danbooru-prompt-reroll ()
  "Generate again from the prompt buffer with a random seed."
  (interactive)
  (danbooru-prompt-generate -1))

(defun danbooru-prompt-preview ()
  "Preview compiled jobs and copy their prompts to the kill ring.
An active region selects complete alternatives inside one grouped :vary,
using the same selection rules as `danbooru-prompt-generate'."
  (interactive)
  (danbooru--preview (danbooru--buffer-text t)))

(defun danbooru--preview (text)
  "Show compiled prompts from TEXT."
  (let* ((jobs (danbooru--expand text))
         (buf (get-buffer-create "*Danbooru preview*")))
    (kill-new (mapconcat (lambda (job) (plist-get job :prompt)) jobs "\n\n"))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%d image(s)\n\n" (length jobs)))
        (cl-loop for job in jobs for index from 1 do
                 (insert (format "%d. %s\nSeed: %s\nParameters: %S\n\n%s\n\n"
                                 index (or (plist-get job :label) "Prompt")
                                 (or (plist-get job :seed) danbooru-seed)
                                 (plist-get job :params) (plist-get job :prompt))))
        (goto-char (point-min))
        (special-mode)
        (setq-local truncate-lines nil)))
    (display-buffer buf)))

(defun danbooru--imenu-create-index ()
  "Index top-level :def names, including unfinished forms.
Ignore definitions inside strings, comments and nested lists."
  (let (index)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "(\\s-*:def\\_>" nil t)
        (let* ((start (match-beginning 0))
               (state (save-excursion (syntax-ppss start))))
          (when (and (zerop (car state)) (not (nth 8 state)))
            (let ((name (save-excursion
                          (condition-case nil
                              (progn (forward-comment (point-max))
                                     (read (current-buffer)))
                            (error nil)))))
              (when (and name (symbolp name) (not (keywordp name)))
                (push (cons (symbol-name name) start) index)))))))
    (when index (list (cons "Blocks" (nreverse index))))))

(defun danbooru--move-definition (backward)
  "Move to the next named definition, or the previous one if BACKWARD."
  (let* ((positions (sort (cl-loop for group in (danbooru--imenu-create-index)
                                  append (mapcar #'cdr (cdr group))) #'<))
         (target (cl-find-if (lambda (position)
                               (if backward (< position (point)) (> position (point))))
                             (if backward (reverse positions) positions))))
    (unless target
      (user-error "danbooru: no %s definition" (if backward "previous" "next")))
    (goto-char target)))

(defun danbooru-next-definition ()
  "Move to the next :def definition."
  (interactive)
  (danbooru--move-definition nil))

(defun danbooru-previous-definition ()
  "Move to the previous :def definition."
  (interactive)
  (danbooru--move-definition t))

(defvar-keymap danbooru-prompt-mode-map
  "M-TAB" #'danbooru-complete-tag
  "M-n" #'danbooru-next-definition
  "M-p" #'danbooru-previous-definition
  "C-c C-j" #'imenu
  "C-c C-c" #'danbooru-prompt-generate
  "C-c C-r" #'danbooru-prompt-reroll
  "C-c C-p" #'danbooru-prompt-preview
  "C-c C-k" #'danbooru-cancel
  "C-c C-s" #'danbooru-toggle-server)

;; Also install additions when reloading into an existing Emacs session.
(define-key danbooru-prompt-mode-map (kbd "M-n") #'danbooru-next-definition)
(define-key danbooru-prompt-mode-map (kbd "M-p") #'danbooru-previous-definition)
(define-key danbooru-prompt-mode-map (kbd "C-c C-j") #'imenu)
(dolist (key '("C-c C-g" "C-c C-v" "C-c C-n"))
  (define-key danbooru-prompt-mode-map (kbd key) nil))

(defun danbooru--setup-navigation ()
  "Install the Danbooru indexer and discard any previously cached index."
  (imenu--cleanup)
  (setq-local imenu-create-index-function #'danbooru--imenu-create-index
              imenu-auto-rescan t
              imenu--index-alist nil
              imenu--last-menubar-index-alist nil
              imenu-menubar-modified-tick -1))

(define-derived-mode danbooru-prompt-mode lisp-data-mode "Danbooru"
  "Edit Danbooru tags for Anima; \\[danbooru-prompt-generate] generates the image.
\\{danbooru-prompt-mode-map}"
  (font-lock-add-keywords
   nil '(("\\$[[:alnum:]_-]+" . font-lock-variable-name-face)
         ("(\\(:[a-z]+\\)" 1 font-lock-keyword-face)))
  (danbooru--setup-navigation)
  (add-hook 'completion-at-point-functions #'danbooru--completion-at-point nil t))

;; Reloading the library does not rerun the mode body in existing buffers.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'danbooru-prompt-mode)
      (danbooru--setup-navigation))))

(add-to-list 'auto-mode-alist '("\\.danbooru\\'" . danbooru-prompt-mode))

(defun danbooru-edit-prompt ()
  "Open `danbooru-prompt-file' for editing in `danbooru-prompt-mode'."
  (interactive)
  (let ((file (expand-file-name danbooru-prompt-file)))
    (pop-to-buffer (find-file-noselect file))
    (when (= (buffer-size) 0)
      (insert danbooru-default-prompt)
      (save-buffer))
    (unless (derived-mode-p 'danbooru-prompt-mode)
      (danbooru-prompt-mode))))

(provide 'danbooru)
;;; danbooru.el ends here
