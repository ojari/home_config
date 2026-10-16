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
;;
;; The file may also be JSON: an array of tags or of arrays of tags (any
;; depth), or an object {"tags": [...], "vary": {"$X": [...]}, "neg": [...],
;; "model": "...", "size": [W, H], "steps": N, "cfg": X, "seed": N}.
;; JSON objects also accept "caption" and "artist".
;;
;; Legacy batches share one seed.  Comic variants share their panel's seed.
;;
;; Comics add named data definitions (see examples/manga.danbooru):
;;   (:character aya :description "A woman" :tags (long_hair hairclip))
;;   (:outfit casual :tags (sweater skirt))
;;   (:scene cafe :tags (cafe) :cast ((aya :outfit casual)))
;;   (:panel greeting :scene cafe :actors ((aya :pose (smiling))))
;; :defaults supplies shared tags and generation options.  Panel-local
;; :vary (($POSE sitting standing)) produces variants only for that panel.
;; C-c C-p previews every job; inside a :panel, C-c C-v previews it,
;; C-c C-g generates it and C-c C-n rerolls it.  Each image has a JSON
;; sidecar recording the source, resolved prompt, parameters and actual seed.
;; C-c C-j opens Imenu, grouped by Characters, Outfits, Scenes and Panels;
;; M-n / M-p move to the next / previous named definition.
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
Named panels overwrite their previous image as PANEL.png.
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
          (list start end (or (danbooru--reference-completions start)
                              (danbooru--tag-completion-table))
                :exclusive 'no))))))

(defun danbooru--reference-completions (start)
  "Return completion candidates for a named reference at START.
Scan definitions without reading the whole buffer, which may be incomplete."
  (let* ((key (save-excursion
                (goto-char start)
                (condition-case nil
                    (progn (backward-sexp) (thing-at-point 'symbol t))
                  (error nil))))
         (kind (pcase key (":scene" ":scene") (":outfit" ":outfit")))
         (open (nth 1 (syntax-ppss start))))
    (when (and (null kind) open
               (string-match-p "\\`[[:space:]]*\\'"
                               (buffer-substring-no-properties (1+ open) start)))
      (setq kind
            (save-excursion
              (goto-char open)
              (condition-case nil
                  (progn (backward-up-list)
                         (backward-sexp)
                         (when (member (thing-at-point 'symbol t) '(":actors" ":cast"))
                           ":character"))
                (error nil)))))
    (when kind
      (let (names)
        (save-excursion
          (goto-char (point-min))
          (while (re-search-forward
                  (concat "(" (regexp-quote kind) "[[:space:]]+\\([^()[:space:]]+\\)") nil t)
            (let ((name (match-string-no-properties 1)) (begin (match-beginning 0)))
              (unless (save-excursion (nth 8 (syntax-ppss begin)))
                (push name names)))))
        ;; An empty completion table still identifies a reference context.
        (or (delete-dups (nreverse names)) (lambda (_string _pred _action) nil))))))

;;; ── Parsing ──

(defconst danbooru--directives
  '(:vary :neg :caption :artist :model :size :steps :cfg :seed
	  :defaults :character :outfit :scene :panel)
  "Keywords that start a directive form.")

(defun danbooru--read-forms (text)
  "Return the list of Lisp forms in TEXT."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (let (forms)
      (while (progn (forward-comment (point-max)) (not (eobp)))
        (let ((line (line-number-at-pos)))
          (condition-case err
              (push (read (current-buffer)) forms)
            (end-of-file
             (user-error "danbooru: incomplete form at line %d" line))
            (error
             (user-error "danbooru: syntax error at line %d: %s"
                         line (error-message-string err))))))
      (nreverse forms))))

(defun danbooru--json-forms (text)
  "Return the JSON prompt TEXT converted to Lisp prompt forms."
  (let* ((data (condition-case err
                   (json-parse-string text :object-type 'alist :array-type 'list
                                      :null-object nil :false-object nil)
                 (json-error (user-error "danbooru: invalid JSON: %s"
                                         (error-message-string err))))))
    (if (not (and (consp data) (consp (car data)) (symbolp (caar data))))
        (if (listp data) data (list data))
      (let (forms)
        (pcase-dolist (`(,key . ,val) data)
          (pcase key
            ('tags (push val forms))
            ('vary (pcase-dolist (`(,marker . ,vals) val)
                     (push (cons :vary (cons marker (ensure-list vals))) forms)))
            ('size (push (cons :size val) forms))
            ('caption (dolist (caption (ensure-list val))
                        (push (list :caption caption) forms)))
            ((or 'neg 'artist 'model 'steps 'cfg 'seed)
             (push (cons (intern (format ":%s" key)) (ensure-list val)) forms))
            (_ (user-error "danbooru: unknown JSON key %s" key))))
        (nreverse forms)))))

(defun danbooru--parse (text)
  "Parse prompt TEXT (Lisp forms or JSON) into a plist.
Keys are :tags (list of tag trees), :caption (list of strings), :vary
(alist of MARKER and value trees), :story (comic definitions), :neg
(tag tree), and generation options."
  (let ((forms (if (string-match-p "\\`[ \t\n]*[[{]" text)
                   (danbooru--json-forms text)
                 (danbooru--read-forms text)))
        tags vary story result)
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
              ((or :defaults :character :outfit :scene :panel)
               (push form story))
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
    (append (list :tags (nreverse tags) :vary (nreverse vary)
                  :story (nreverse story)) result)))

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

(defun danbooru--expand-legacy (p)
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

;;; ── Comic definitions and compilation ──

(defconst danbooru--parameter-keys '(:model :size :steps :cfg :seed))

(defun danbooru--properties (props allowed context)
  "Validate PROPS against ALLOWED keys, reporting errors in CONTEXT."
  (unless (and (proper-list-p props) (zerop (% (length props) 2)))
    (user-error "danbooru: %s needs keyword/value pairs" context))
  (let (seen)
    (cl-loop for (key value) on props by #'cddr do
             (unless (memq key allowed)
               (user-error "danbooru: unknown property %s in %s" key context))
             (when (memq key seen)
               (user-error "danbooru: duplicate property %s in %s" key context))
             (push key seen)
             (when (memq key '(:description :action :caption))
               (unless (stringp value)
                 (user-error "danbooru: %s in %s must be a string" key context)))
             (when (memq key '(:tags :neg :camera :pose :expression))
               (danbooru--validate-tags value context))
             (when (eq key :vary)
               (unless (and (proper-list-p value)
                            (cl-every (lambda (entry)
                                        (and (consp entry) (proper-list-p entry)
                                             (cdr entry))) value))
                 (user-error "danbooru: invalid :vary in %s" context)))))
  (danbooru--validate-parameters props context)
  props)

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

(defun danbooru--definition (name table kind)
  "Find NAME in TABLE or report an unknown KIND reference."
  (or (assq name table)
      (user-error "danbooru: unknown %s %S" kind name)))

(defun danbooru--actors (actors characters outfits context &optional cast)
  "Validate ACTORS and their references in CONTEXT.
CAST means these are scene defaults rather than panel actors."
  (unless (proper-list-p actors)
    (user-error "danbooru: %s must be a list of actors" context))
  (let (seen)
    (dolist (actor actors)
      (unless (and (consp actor) (proper-list-p actor))
        (user-error "danbooru: invalid actor %S in %s" actor context))
      (let ((name (car actor)) (props (cdr actor)))
        (danbooru--definition name characters "character")
        (when (memq name seen)
          (user-error "danbooru: duplicate actor %s in %s" name context))
        (push name seen)
        (danbooru--properties
         props (if cast '(:outfit) '(:outfit :position :pose :expression :tags)) context)
        (when (plist-get props :outfit)
          (danbooru--definition (plist-get props :outfit) outfits "outfit"))
        (when (plist-member props :position)
          (unless (or (stringp (plist-get props :position))
                      (and (symbolp (plist-get props :position))
                           (plist-get props :position)
                           (not (keywordp (plist-get props :position)))))
            (user-error "danbooru: invalid position in %s" context)))))))

(defun danbooru--story (p)
  "Resolve and validate the comic definitions in parsed prompt P."
  (let (characters outfits scenes panels defaults defaults-seen)
    (when (plist-get p :vary)
      (user-error "danbooru: put comic variations in a panel's :vary property"))
    (dolist (form (plist-get p :story))
      (unless (proper-list-p form)
        (user-error "danbooru: invalid definition %S" form))
      (let ((kind (car form)) (name (cadr form)) (props (cddr form)))
        (if (eq kind :defaults)
            (progn
              (when defaults-seen (user-error "danbooru: duplicate :defaults"))
              (setq defaults-seen t
                    defaults (danbooru--properties
                              (cdr form) (append '(:tags :neg :caption) danbooru--parameter-keys)
                              "defaults")))
          (unless (and name (symbolp name) (not (keywordp name)))
            (user-error "danbooru: %s needs a symbolic name" kind))
          (danbooru--properties
           props
           (pcase kind
             (:character '(:description :tags))
             (:outfit '(:tags))
             (:scene '(:tags :neg :caption :cast))
             (:panel (append '(:scene :actors :camera :tags :caption :action :neg :vary)
                             danbooru--parameter-keys)))
           (format "%s %s" kind name))
          (pcase kind
            (:character (push (cons name props) characters))
            (:outfit (push (cons name props) outfits))
            (:scene (push (cons name props) scenes))
            (:panel (push (cons name props) panels))))))
    (dolist (table (list characters outfits scenes panels))
      (let (seen)
        (dolist (entry table)
          (when (memq (car entry) seen)
            (user-error "danbooru: duplicate definition %s" (car entry)))
          (push (car entry) seen))))
    (unless panels (user-error "danbooru: comic has no panels"))
    ;; Validate all references, including definitions not used by a panel.
    (dolist (scene scenes)
      (danbooru--actors (plist-get (cdr scene) :cast) characters outfits
                        (format "scene %s" (car scene)) t))
    (dolist (panel panels)
      (let ((props (cdr panel)))
        (danbooru--definition (plist-get props :scene) scenes "scene")
        (danbooru--actors (plist-get props :actors) characters outfits
                          (format "panel %s" (car panel)))))
    (list :characters characters :outfits outfits :scenes scenes
          :panels (nreverse panels) :defaults defaults)))

(defun danbooru--merge-properties (&rest layers)
  "Merge LAYERS of properties; later layers override earlier ones."
  (let (result)
    (dolist (layer layers)
      (cl-loop for (key value) on layer by #'cddr do
               (setq result (plist-put result key value))))
    result))

(defun danbooru--position (position combo)
  "Render actor POSITION as a spatial phrase, resolving COMBO."
  (let ((text (danbooru--join (danbooru--flatten position combo))))
    (cond ((string-empty-p text) "")
          ((member text '("left" "right")) (concat " on the " text))
          ((member text '("center" "foreground" "background"))
           (concat " in the " text))
          ((string-match-p "\\`\\(on\\|in\\|at\\|to\\|behind\\|beside\\|between\\|near\\|under\\|above\\|below\\|next to\\)\\b" text)
           (concat " " text))
          (t (concat " at " text)))))

(defun danbooru--actor-prompt (actor cast story combo)
  "Render ACTOR with CAST outfit defaults from STORY and variation COMBO."
  (let* ((name (car actor))
         (character (cdr (assq name (plist-get story :characters))))
         (props (danbooru--merge-properties (cdr (assq name cast)) (cdr actor)))
         (outfit (cdr (assq (plist-get props :outfit) (plist-get story :outfits))))
         (description (danbooru--join
                       (danbooru--flatten (or (plist-get character :description)
                                              "A person") combo)))
         (position (plist-get props :position))
         (tags (danbooru--join
                (danbooru--flatten
                 (list (plist-get character :tags) (plist-get outfit :tags)
                       (plist-get props :pose) (plist-get props :expression)
                       (plist-get props :tags)) combo))))
    (danbooru--sentence
     (concat (if (or position (not (string-empty-p tags)))
                 (string-remove-suffix "." description)
               description)
             (when position (danbooru--position position combo))
             (unless (string-empty-p tags) (concat ": " tags))))))

(defun danbooru--expand-story (p)
  "Compile parsed comic P into an ordered list of panel jobs."
  (let* ((story (danbooru--story p))
         (defaults (plist-get story :defaults)))
    (cl-loop
     for (name . panel) in (plist-get story :panels) append
     (let* ((scene (cdr (assq (plist-get panel :scene) (plist-get story :scenes))))
            (cast (plist-get scene :cast))
            (actors (if (plist-member panel :actors) (plist-get panel :actors) cast))
            (options (danbooru--merge-properties
                      (cl-loop for key in danbooru--parameter-keys
                               when (plist-member p key)
                               append (list key (plist-get p key)))
                      defaults panel))
            (neg (list (plist-get p :neg) (plist-get defaults :neg)
                       (plist-get scene :neg) (plist-get panel :neg)))
            (tags (list (plist-get p :tags) (plist-get defaults :tags)
                        (plist-get scene :tags) (plist-get panel :camera)
                        (plist-get panel :tags)))
            (captions (list (plist-get p :caption) (plist-get defaults :caption)
                            (plist-get scene :caption) (plist-get panel :caption)))
            (vary (plist-get panel :vary))
            (combos (list nil))
            (all (prin1-to-string
                  (list tags neg captions (plist-get panel :action)
                        (mapcar #'cdr vary)
                        (mapcar (lambda (actor)
                                  (danbooru--actor-prompt actor cast story nil)) actors)))))
       (unless (proper-list-p vary)
         (user-error "danbooru: :vary in panel %s must be a list" name))
       (let (seen)
         (dolist (variation vary)
           (unless (and (proper-list-p variation) (cdr variation)
                        (string-match-p "\\`\\$[[:alnum:]_-]+\\'"
                                        (format "%s" (car variation))))
             (user-error "danbooru: invalid variation in panel %s: %S" name variation))
           (let ((marker (format "%s" (car variation))))
             (when (member marker seen)
               (user-error "danbooru: duplicate variation %s in panel %s" marker name))
             (push marker seen)
             (unless (string-search marker all)
               (user-error "danbooru: placeholder %s does not occur in panel %s" marker name))
             (dolist (value (cdr variation))
               (danbooru--validate-tags value (format "variation in panel %s" name)))
             (setq combos (cl-loop for combo in combos append
                                   (cl-loop for value in (cdr variation)
                                            collect (append combo (list (cons marker value)))))))))
       (mapcar
        (lambda (combo)
          (let* ((size (or (plist-get options :size) (list danbooru-width danbooru-height)))
                 (action (danbooru--join (danbooru--flatten (plist-get panel :action) combo)))
                 (prompt
                  (string-join
                   (append
                    (let ((global (danbooru--join (danbooru--flatten tags combo))))
                      (unless (string-empty-p global) (list (danbooru--sentence global))))
                    (list (if actors (format "%d %s." (length actors)
                                             (if (cdr actors) "people" "person"))
                            "No people."))
                    (mapcar (lambda (actor) (danbooru--actor-prompt actor cast story combo)) actors)
                    (danbooru--captions captions combo)
                    (unless (string-empty-p action) (list (danbooru--sentence action))))
                   " ")))
            ;; Remaining markers are almost always misspelled references.
            (when (string-match "\\$[[:alpha:]_][[:alnum:]_-]*" prompt)
              (user-error "danbooru: unresolved placeholder %s in panel %s"
                          (match-string 0 prompt) name))
            (let ((negative (danbooru--join (danbooru--flatten neg combo))))
              (when (string-match "\\$[[:alpha:]_][[:alnum:]_-]*" negative)
                (user-error "danbooru: unresolved placeholder %s in panel %s"
                            (match-string 0 negative) name))
              (list :panel name
                    :label (concat (symbol-name name)
                                   (when combo
                                     (concat " / " (mapconcat
                                                    (lambda (entry)
                                                      (danbooru--join
                                                       (danbooru--flatten (cdr entry) combo)))
                                                    combo " / "))))
                    :prompt prompt :seed (plist-get options :seed)
                    :params (list :model (format "%s" (or (plist-get options :model) danbooru-model))
                                  :width (car size) :height (cadr size)
                                  :steps (if (plist-member options :steps)
                                             (plist-get options :steps) danbooru-steps)
                                  :cfg (if (plist-member options :cfg)
                                           (plist-get options :cfg) danbooru-cfg)
                                  :neg (unless (string-empty-p negative) negative))))))
        combos)))))

(defun danbooru--expand (text &optional panel)
  "Compile TEXT into jobs, optionally selecting only PANEL.
Legacy prompts retain their batch variation behavior.  Comics produce
ordered panels with variations local to each panel."
  (let* ((p (danbooru--parse text))
         (_ (danbooru--validate-parameters p "prompt"))
         (jobs (if (plist-get p :story)
                   (danbooru--expand-story p)
                 (danbooru--expand-legacy p))))
    (if (null panel) jobs
      (or (cl-remove-if-not (lambda (job) (eq (plist-get job :panel) panel)) jobs)
          (user-error "danbooru: unknown panel %s" panel)))))

;;; ── Running ──

(defun danbooru--slug (s)
  "Return S as a short file-name-safe string."
  (let ((slug (string-trim (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase s))
                           "-+" "-+")))
    (substring slug 0 (min 40 (length slug)))))

(defun danbooru--output-file (stamp &optional index label panel)
  "Return output file name for timestamp STAMP.
Named PANEL uses a stable filename, replacing its previous image.
For legacy batches INDEX and LABEL are added to STAMP.
Use the current prompt file's basename as a subdirectory when available."
  (let ((dir (if buffer-file-name
                 (expand-file-name (file-name-base buffer-file-name)
                                   danbooru-output-dir)
               (expand-file-name danbooru-output-dir))))
    (make-directory dir t)
    (expand-file-name (cond (panel (concat (danbooru--slug (symbol-name panel)) ".png"))
                            (index (format "anima-%s-%02d-%s.png" stamp index (danbooru--slug label)))
                            (t (format "anima-%s.png" stamp)))
                      dir)))

(defun danbooru-generate (text &optional seed panel)
  "Generate images from prompt TEXT asynchronously.
TEXT is in the prompt file format, see the commentary; a plain comma
separated tag string also works.  One image is made per :vary
combination or comic panel.  PANEL selects a named panel and its variants.
Panel variants and rerolls replace the panel's previous image.
SEED overrides all file seeds.  Random seeds are shared by the variants
of a panel (or a legacy batch), and saved alongside each image.  If a
generation is running, the new images are queued after it."
  (when seed (danbooru--validate-parameters (list :seed seed) "seed override"))
  (danbooru--enqueue-jobs (danbooru--expand text panel) text seed))

(defun danbooru--enqueue-jobs (jobs text &optional seed)
  "Queue compiled JOBS with source TEXT and optional overriding SEED."
  (let* ((random-seeds (make-hash-table :test #'eq))
         (stamp (format-time-string "%Y%m%d-%H%M"))
         (batch (or (cdr jobs) (plist-get (car jobs) :panel)))
         (index 0))
    (setq danbooru-last-source text)
    (unless (process-live-p danbooru--process)
      (setq danbooru--batch nil
            danbooru--batch-size 0)
      (with-current-buffer (get-buffer-create "*danbooru-log*")
        (erase-buffer)))
    (dolist (job jobs)
      (let* ((label (plist-get job :label))
             (id (plist-get job :panel))
             (requested (or seed (plist-get job :seed) danbooru-seed))
             (actual (if (>= requested 0) requested
                       (or (gethash id random-seeds)
                           (puthash id (random 2147483647) random-seeds)))))
        (setq danbooru--queue
              (append danbooru--queue
                      (list (list :prompt (plist-get job :prompt) :params (plist-get job :params)
                                  :seed actual :label label :source text :panel id
                                  :server danbooru-server
                                  :out (danbooru--output-file
                                        stamp (and batch (cl-incf index)) label id)))))))
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
    (cl-destructuring-bind (&key prompt params seed out label source panel server)
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
                            (danbooru--save-metadata out source panel prompt params seed server)
                          (error (with-current-buffer log
                                   (goto-char (point-max))
                                   (insert (format "metadata error: %s\n"
                                                   (error-message-string err))))))
                        (danbooru-show out source panel)
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
(defvar-local danbooru-panel nil "Comic panel that produced this image.")

(defun danbooru--save-metadata (out source panel prompt params seed server)
  "Save the inputs that produced OUT to a neighboring JSON file."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file (concat out ".json")
      (insert (json-serialize
               (list :version 1 :source source
                     :panel (if panel (symbol-name panel) :null)
                     :prompt prompt :seed seed
                     :requested_parameters (danbooru--obj params)
                     :backend (or server (expand-file-name danbooru-script)))))
      (insert "\n"))))

(defun danbooru-show (file &optional source panel)
  "Show image FILE in image-mode, remembering SOURCE as its prompt."
  (let* ((existing (get-file-buffer file))
         (buf (or existing (find-file-noselect file))))
    (with-current-buffer buf
      (when existing (revert-buffer t t))
      (setq danbooru-source source danbooru-panel panel))
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
    (danbooru-generate text -1 danbooru-panel)))

;;; ── Prompt file ──

(defvar danbooru-default-prompt
  ";;; Anima prompt  -*- mode: danbooru-prompt -*-
;; C-c C-c generate   C-c C-r new seed   C-c C-p show flat prompt   C-c C-k cancel
;; C-c C-s toggle sd-server (M-x danbooru-start-server to run one locally)
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

(defun danbooru--buffer-text ()
  "Return the prompt text of the current buffer."
  (buffer-substring-no-properties (point-min) (point-max)))

(defun danbooru-prompt-generate (&optional seed)
  "Save the prompt buffer, flatten its tags and generate the image(s)."
  (interactive)
  (when buffer-file-name (save-buffer))
  (danbooru-generate (danbooru--buffer-text) seed))

(defun danbooru-prompt-reroll ()
  "Generate again from the prompt buffer with a random seed."
  (interactive)
  (danbooru-prompt-generate -1))

(defun danbooru-prompt-preview ()
  "Preview every compiled job and copy its prompt to the kill ring."
  (interactive)
  (danbooru--preview (danbooru--buffer-text)))

(defun danbooru--preview (text &optional panel)
  "Show compiled prompts from TEXT, optionally selecting PANEL."
  (let* ((jobs (danbooru--expand text panel))
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

(defun danbooru--panel-at-point ()
  "Return the name of the top-level :panel form containing point."
  (with-syntax-table emacs-lisp-mode-syntax-table
    (save-excursion
      (let ((position (point)))
	(goto-char (point-min))
	(catch 'found
          (while (progn (forward-comment (point-max)) (not (eobp)))
            (let ((start (point)) (form (read (current-buffer))))
              (when (and (<= start position) (<= position (point))
			 (consp form) (eq (car form) :panel))
		(throw 'found (cadr form)))))
          (user-error "danbooru: move point into a :panel form"))))))

(defun danbooru-prompt-generate-panel (&optional seed)
  "Generate the panel at point and its variants, optionally overriding SEED."
  (interactive)
  (let ((panel (danbooru--panel-at-point)))
    (when buffer-file-name (save-buffer))
    (danbooru-generate (danbooru--buffer-text) seed panel)))

(defun danbooru-prompt-reroll-panel ()
  "Generate the panel at point with a new random seed."
  (interactive)
  (danbooru-prompt-generate-panel -1))

(defun danbooru-prompt-preview-panel ()
  "Preview only the panel at point and its variants."
  (interactive)
  (danbooru--preview (danbooru--buffer-text) (danbooru--panel-at-point)))

(defun danbooru--imenu-create-index ()
  "Index named top-level definitions, including unfinished forms.
Ignore definitions inside strings, comments and nested lists."
  (let ((groups '((":character" . "Characters") (":outfit" . "Outfits")
                  (":scene" . "Scenes") (":panel" . "Panels")))
        index)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "(\\s-*\\(:character\\|:outfit\\|:scene\\|:panel\\)\\_>" nil t)
        (let* ((start (match-beginning 0))
               (group (cdr (assoc (match-string-no-properties 1) groups)))
               (state (save-excursion (syntax-ppss start))))
          (when (and (zerop (car state)) (not (nth 8 state)))
            (let ((name (save-excursion
                          (condition-case nil
                              (progn (forward-comment (point-max))
                                     (read (current-buffer)))
                            (error nil)))))
              (when (and name (symbolp name) (not (keywordp name)))
                (let ((entry (assoc group index)))
                  (unless entry
                    (setq entry (list group))
                    (push entry index))
                  (push (cons (symbol-name name) start) (cdr entry)))))))))
    (cl-loop for (_kind . group) in groups
             for entry = (assoc group index)
             when entry collect (cons group (nreverse (cdr entry))))))

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
  "Move to the next character, outfit, scene or panel definition."
  (interactive)
  (danbooru--move-definition nil))

(defun danbooru-previous-definition ()
  "Move to the previous character, outfit, scene or panel definition."
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
  "C-c C-g" #'danbooru-prompt-generate-panel
  "C-c C-v" #'danbooru-prompt-preview-panel
  "C-c C-n" #'danbooru-prompt-reroll-panel
  "C-c C-k" #'danbooru-cancel
  "C-c C-s" #'danbooru-toggle-server)

;; Also install additions when reloading into an existing Emacs session.
(define-key danbooru-prompt-mode-map (kbd "M-n") #'danbooru-next-definition)
(define-key danbooru-prompt-mode-map (kbd "M-p") #'danbooru-previous-definition)
(define-key danbooru-prompt-mode-map (kbd "C-c C-j") #'imenu)
(define-key danbooru-prompt-mode-map (kbd "C-c C-g") #'danbooru-prompt-generate-panel)
(define-key danbooru-prompt-mode-map (kbd "C-c C-v") #'danbooru-prompt-preview-panel)
(define-key danbooru-prompt-mode-map (kbd "C-c C-n") #'danbooru-prompt-reroll-panel)

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
