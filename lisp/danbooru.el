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

(require 'danbooru-catalog
         (expand-file-name "danbooru-catalog"
                           (file-name-directory (or load-file-name
                                                    (bound-and-true-p byte-compile-current-file)
                                                    buffer-file-name))))
(when (and (boundp 'danbooru-tag-file)
           (not (eq (indirect-variable 'danbooru-tag-file) 'danbooru-catalog-tag-file)))
  (setq danbooru-catalog-tag-file (symbol-value 'danbooru-tag-file)))
(defvaralias 'danbooru-tag-file 'danbooru-catalog-tag-file)

(defcustom danbooru-profiles nil
  "Explicit language profiles: (NAME . SETTINGS-PLIST).
Settings include :width, :height, :steps, :cfg, :style, :prefix,
:sampler and :scheduler.  Backend selection remains execution state."
  :type '(alist :key-type string :value-type plist) :group 'danbooru)

(defvar danbooru-last-source nil "Prompt text of the last run.")
(defvar danbooru-history nil "History for `danbooru'.")
(defvar danbooru--process nil)
(defvar danbooru--queue nil "Pending generations, plists of :prompt :env :seed :out :label.")
(defvar danbooru--batch nil "Output files of the current batch.")
(defvar danbooru--batch-size 0 "Number of images in the current batch.")
(defun danbooru--tag-completion-table ()
  "Return serialized candidates from the catalog shared with the builder."
  (danbooru-catalog-completions (danbooru-catalog-get)))

(defun danbooru-complete-tag ()
  "Complete the Danbooru tag at point.
Invoke repeatedly to insert multiple tags in a prompt list."
  (interactive)
  (completion-at-point))

(defun danbooru--completion-at-point ()
  "Complete explicit references, lexical names, directives or ordinary tags."
  (unless (or (nth 3 (syntax-ppss)) (nth 4 (syntax-ppss)))
    (let ((end (point)) (context (danbooru--reference-context)))
      (save-excursion
        (skip-chars-backward "[:alnum:]_:/?+*!@%=-")
        (let ((start (point)))
          (list start end
                (pcase context
                  (:ref (danbooru--library-block-names))
                  (:var (mapcar #'car (danbooru--lexical-bindings-at-point)))
                  (_ (append (danbooru--library-block-names)
                             (mapcar #'symbol-name (append danbooru--directives '(:def :include :ref :var :let)))
                             (danbooru--tag-completion-table))))
                :exclusive 'no))))))

(defun danbooru--reference-context ()
  "Return :ref or :var when point is completing the form's name slot."
  (let ((position (point)) (parent (nth 1 (syntax-ppss))))
    (when parent
      (save-excursion
        (goto-char (1+ parent))
        (condition-case nil
            (let ((head (read (current-buffer))))
              (forward-comment (point-max))
              (when (and (memq head '(:ref :var)) (<= (point) position)
                         (or (= (point) position) (>= (scan-sexps (point) 1) position))) head))
          (error nil))))))

(defun danbooru--lexical-bindings-at-point ()
  "Return lexical (NAME . POSITION) pairs visible at point, inner first.
Let initializers see only outer bindings; block bodies see their parameters."
  (let ((position (point)) (parent (nth 1 (syntax-ppss))) bindings)
    (save-excursion
      (while parent
        (goto-char (1+ parent))
        (condition-case nil
            (pcase (read (current-buffer))
              (:def
               (read (current-buffer))
               (forward-comment (point-max))
               (let ((start (point)) (params (read (current-buffer))))
                 (when (and (< (point) position) (proper-list-p params)
                            (cl-every #'danbooru-language--local-name-p params))
                   (goto-char (1+ start))
                   (dolist (name params)
                     (forward-comment (point-max))
                     (setq bindings (append bindings (list (cons (symbol-name name) (point)))))
                     (read (current-buffer))))))
              (:let
               (forward-comment (point-max))
               (let ((start (point)) (values (read (current-buffer))))
                 (when (and (< (point) position) (proper-list-p values))
                   (goto-char (1+ start))
                   (dolist (binding values)
                     (forward-comment (point-max))
                     (let ((end (scan-sexps (point) 1)))
                       (forward-char 1) (forward-comment (point-max))
                       (when (and (consp binding) (danbooru-language--local-name-p (car binding)))
                         (setq bindings (append bindings (list (cons (symbol-name (car binding)) (point))))))
                       (goto-char end)))))))
          (error nil))
        (setq parent (nth 1 (syntax-ppss parent)))))
    (cl-delete-duplicates bindings :key #'car :test #'equal :from-end t)))

(defun danbooru-find-reference ()
  "Visit a global definition or the lexical binder referenced at point."
  (interactive)
  (let* ((name (thing-at-point 'symbol t))
         (context (danbooru--reference-context))
         (binding (and (eq context :var) (assoc name (danbooru--lexical-bindings-at-point)))))
    (unless name (user-error "No reference name at point"))
    (if binding (progn (push-mark) (goto-char (cdr binding)))
      (when (eq context :var) (user-error "Unbound lexical variable %s" name))
      (let* ((source (buffer-substring-no-properties (point-min) (point-max)))
             (compile-context (list :file (and buffer-file-name (file-truename buffer-file-name))
                                    :directory default-directory :read-source #'danbooru-runtime-read-source))
             (compilation (danbooru-language-compile source compile-context))
             (definition (cl-find (intern name) (danbooru-compilation-definitions compilation) :key #'danbooru-definition-name)))
        (unless definition
          ;; Preserve original ranges when an unfinished trailing form prevents
          ;; reading the full source.  Earlier complete forms still navigate.
          (let ((end (point-min)))
            (save-excursion
              (goto-char (point-min))
              (condition-case nil
                  (while (progn (forward-comment (point-max)) (not (eobp)))
                    (read (current-buffer)) (setq end (point)))
                (error nil)))
            (setq compilation (danbooru-language-compile (buffer-substring-no-properties (point-min) end) compile-context)
                  definition (cl-find (intern name) (danbooru-compilation-definitions compilation) :key #'danbooru-definition-name))))
        (unless definition (user-error "No definition for %s" name))
        (let* ((node (danbooru-definition-node definition))
               (file (danbooru-source-node-file node)))
          (push-mark)
          (when file (pop-to-buffer (find-file-noselect file)))
          (goto-char (danbooru-source-node-start node)))))))


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
        (let* ((danbooru-language--read-source-function #'danbooru-runtime-read-source)
               (collected (danbooru--include-forms
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

;;; ── Compiler compatibility ──

(require 'danbooru-language
         (expand-file-name "danbooru-language"
                           (file-name-directory
                            (or load-file-name
                                (bound-and-true-p byte-compile-current-file)
                                buffer-file-name))))

(defvar-local danbooru--last-compilation nil)
(defvar-local danbooru--last-compilation-text nil)
(defvar-local danbooru--prepared nil)
(defvar-local danbooru--prepared-text nil)

(defun danbooru--expand (text &optional directory overrides)
  "Compile TEXT into legacy jobs, raising `user-error' for invalid input.
DIRECTORY is the include base; OVERRIDES is an explicit run-settings plist.
New clients should use
`danbooru-language-compile' to retain diagnostics and provenance."
  (let* ((context (list :file buffer-file-name
                        :directory (or directory
                                       (and buffer-file-name
                                            (file-name-directory buffer-file-name))
                                       default-directory)
                        :read-source #'danbooru-runtime-read-source
                        :overrides overrides :profiles danbooru-profiles :seed danbooru-seed
                        :model danbooru-model :width danbooru-width
                        :height danbooru-height :steps danbooru-steps :cfg danbooru-cfg
                        :lowercase-tags danbooru-lowercase-tags
                        :underscore-to-space danbooru-underscore-to-space))
         (compilation (danbooru-language-compile text context))
         (diagnostic (car (danbooru-compilation-errors compilation))))
    (when diagnostic
      (user-error "%s" (danbooru-diagnostic-message diagnostic)))
    (setq danbooru--last-compilation compilation danbooru--last-compilation-text text)
    (mapcar (lambda (job)
              (cl-loop for key in (append '(:label :prompt :seed :params :source)
                                          (and (plist-member job :execution-context) '(:execution-context)))
                       append (list key (danbooru-language--plain (plist-get job key)))))
            (danbooru-compilation-jobs compilation))))

(require 'danbooru-runtime
         (expand-file-name "danbooru-runtime"
                           (file-name-directory (or load-file-name
                                                    (bound-and-true-p byte-compile-current-file)
                                                    buffer-file-name))))

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
combination for each requested seed.  SEED overrides the file seed/range.
Random seeds are shared by
all variants in this batch and saved alongside each image.  If a
generation is running, the new images are queued after it."
  (when seed
    (unless (integerp seed) (user-error "danbooru: seed override must be an integer"))
    (danbooru--validate-parameters (list :seed seed) "seed override"))
  (danbooru--enqueue-jobs
   (if (and (not seed) (equal text danbooru--prepared-text) (danbooru-runtime-current-p danbooru--prepared text))
       (danbooru-prepared-jobs danbooru--prepared)
     (danbooru--expand text nil (and seed (list :seed seed)))) text seed))

(defun danbooru--prepare-jobs (jobs text &optional seed)
  "Prepare JOBS, reusing a matching preview unless SEED explicitly overrides it."
  (if (and (not seed) (equal text danbooru--prepared-text) (danbooru-runtime-current-p danbooru--prepared text))
      danbooru--prepared
    (let* ((plan (if (and danbooru--last-compilation (equal text danbooru--last-compilation-text))
                     (danbooru-runtime-plan danbooru--last-compilation nil (current-buffer))
                   (danbooru-runtime-plan-from-jobs jobs text (current-buffer))))
           (context (danbooru-runtime-context)))
      (when seed
        (setf (danbooru-runtime-plan-jobs plan)
              (mapcar (lambda (job) (plist-put job :seed seed)) (danbooru-runtime-plan-jobs plan))))
      (setq danbooru--prepared (danbooru-runtime-prepare plan context)
            danbooru--prepared-text text)
      danbooru--prepared)))

(defun danbooru--enqueue-jobs (jobs text &optional seed)
  "Prepare and submit JOBS through the shared runtime, reusing the preview."
  (let ((prepared (danbooru--prepare-jobs jobs text seed)))
    (setq danbooru-last-source (or (plist-get (car (danbooru-prepared-jobs prepared)) :source) text))
    (prog1 (danbooru-runtime-submit prepared)
      (setq danbooru--prepared nil danbooru--prepared-text nil))))

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
                       (danbooru-catalog-candidates (danbooru-catalog-get))
                       nil nil nil 'danbooru-history)
                      ", ")))
  (danbooru-generate (prin1-to-string (string-trim tags))))

(defun danbooru-regenerate ()
  "Run the last prompt (or this image's prompt) again with a random seed."
  (interactive)
  (when (and (local-variable-p 'danbooru-source) (null danbooru-source))
    (user-error "danbooru: this image has no prompt file source%s"
                (if (fboundp 'danbooru-builder-open-image)
                    "; M-x danbooru-builder-open-image loads its builder setup"
                  "")))
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
  "Prepare TEXT and show the exact frozen batch the next Generate submits."
  (let ((prepared (danbooru--prepare-jobs (danbooru--expand text) text)))
    (kill-new (mapconcat (lambda (job) (plist-get job :prompt)) (danbooru-prepared-jobs prepared) "\n\n"))
    (danbooru-runtime-preview prepared)))

(defun danbooru-inspect-image (file)
  "Inspect FILE's saved request and source snapshots without recompiling."
  (interactive "fImage or metadata: ")
  (let* ((prepared (danbooru-runtime-restore file))
         (job (car (danbooru-prepared-jobs prepared))))
    (danbooru-runtime-inspect-job
     (make-danbooru-run-job :id (plist-get job :id) :run-id (plist-get job :run-id)
                            :data job :state 'completed))))

(defun danbooru-replay (file)
  "Replay FILE's saved backend request with its recorded seed."
  (interactive "fImage or metadata to replay: ")
  (danbooru-runtime-replay file))

(defun danbooru-replay-reroll (file)
  "Replay FILE's saved request with one freshly chosen seed."
  (interactive "fImage or metadata to reroll: ")
  (danbooru-runtime-replay file t))

(defun danbooru-recompile-image (file)
  "Generate from the latest root/library source associated with FILE."
  (interactive "fImage or metadata: ")
  (let* ((prepared (danbooru-runtime-restore file))
         (root (car (danbooru-prepared-sources prepared)))
         (path (plist-get root :file)))
    (unless (and path (file-readable-p path)) (user-error "Latest source file is unavailable; exact replay remains available"))
    (with-current-buffer (find-file-noselect path)
      (save-restriction (widen) (danbooru-generate (buffer-substring-no-properties (point-min) (point-max)))))))

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

(autoload 'danbooru-groups-pick "danbooru-groups" nil t)

(defvar-keymap danbooru-prompt-mode-map
  "M-TAB" #'danbooru-complete-tag
  "M-." #'danbooru-find-reference
  "M-n" #'danbooru-next-definition
  "M-p" #'danbooru-previous-definition
  "C-c C-j" #'imenu
  "C-c C-t" #'danbooru-groups-pick
  "C-c C-c" #'danbooru-prompt-generate
  "C-c C-r" #'danbooru-prompt-reroll
  "C-c C-p" #'danbooru-prompt-preview
  "C-c C-k" #'danbooru-cancel
  "C-c C-s" #'danbooru-toggle-server)

;; Also install additions when reloading into an existing Emacs session.
(define-key danbooru-prompt-mode-map (kbd "M-.") #'danbooru-find-reference)
(define-key danbooru-prompt-mode-map (kbd "M-n") #'danbooru-next-definition)
(define-key danbooru-prompt-mode-map (kbd "M-p") #'danbooru-previous-definition)
(define-key danbooru-prompt-mode-map (kbd "C-c C-j") #'imenu)
(define-key danbooru-prompt-mode-map (kbd "C-c C-t") #'danbooru-groups-pick)
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
