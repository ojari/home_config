;;; danbooru-builder.el --- Build Anima prompts from a Danbooru tag catalog -*- lexical-binding: t; -*-

;;; Commentary:
;; An Emacs front end for the tag catalog of ~/source/get_tags (builder.py):
;; tags/*.json (categories -> groups -> tags), tags/vocab/*.csv (the Danbooru
;; vocabulary) and config.json (category order, defaults, model profiles).
;;
;; M-x danbooru-builder opens *danbooru-builder*: one line per chosen tag,
;; under a Scene heading and one heading per person, grouped by category in
;; Anima prompt order.  The flat prompt is shown at the bottom.
;;
;; The section point is in decides who a new tag belongs to; categories in
;; `danbooru-builder--scene-categories' (quality, camera, lighting, ...)
;; always go to the scene.  Count tags (1girl, 2girls) come from the
;; persons once there are any.
;;
;; A variation is one tag slot holding alternatives, each alternative one
;; or more comma separated tags.  Every combination of the variations is
;; one image.  Alternatives can be switched off without removing them.
;;
;;   a      add tags (catalog + Danbooru vocabulary, free text for custom)
;;   A      add tags of one category (default: the category at point)
;;   T      add free-form text under the category at point (or choose one)
;;   t      change the category of the free-form text at point
;;   k      remove the text, tag, alternative, marked tags or person at point
;;   RET    edit text, tag / alternative, add alternatives, edit person
;;   M-up/M-down  move a tag within its category, an alternative, or free text
;;   m u U  mark, unmark, unmark all
;;   v      make a variation of the tag at point or the marked tags,
;;          or split the variation at point back into tags
;;   x      switch the alternative at point off or on
;;   i      show the latest generated image for the alternative at point
;;   l      link the variation at point with others: linked variations
;;          step together (1st with 1st, 2nd with 2nd) instead of combining
;;   P e    add a person, edit the person at point
;;   s      settings menu: profile, size, steps, cfg, sampler, seeds,
;;          prompt style, negative prompt, extra text
;;   w      copy the prompt (first variant)
;;   C-c C-c  generate: every variant for every seed, through danbooru.el
;;   C-c C-p  list the prompts the next generate makes
;;   C-c C-k  cancel the running and queued images
;;   C-x C-s  save to a .dbb file, C-x C-w save as, o open one, N new
;;   E      export to a .danbooru prompt file (danbooru-prompt-mode)
;;
;; A .dbb file is readable Lisp data: the tags, persons, variations and
;; settings.  Visiting one shows its text; C-c C-c loads it.
;; Free-form text blocks (T) keep their spelling and punctuation and follow
;; the tags in their category, under the current person or Scene.  RET edits,
;; t changes category and M-up/M-down reorders text within that category.
;; Older files with numbered text positions still load in the Prompt order
;; view; t moves such a block into a category.
;;
;; Images go to output_dir of config.json.  The backend is sd-cli with
;; the profile's model arguments, or an sd-server URL (settings menu).
;;   g      reload the tag files

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)
(require 'crm)
(require 'text-property-search)
(require 'transient)
(require 'danbooru (expand-file-name
                    "danbooru" (file-name-directory
                                (or load-file-name
                                    (bound-and-true-p byte-compile-current-file)
                                    buffer-file-name))))

(declare-function danbooru-builder-source-convert "danbooru-builder-source" (data catalog &optional skip-parity))
(declare-function danbooru-builder-import "danbooru-builder-source" (file &optional destination catalog))

;;; ── Settings ──

(defgroup danbooru-builder nil
  "Build Anima prompts from a Danbooru tag catalog."
  :group 'multimedia)

(when (and (boundp 'danbooru-builder-directory)
           (not (eq (indirect-variable 'danbooru-builder-directory) 'danbooru-catalog-directory)))
  (setq danbooru-catalog-directory (symbol-value 'danbooru-builder-directory)))
(defvaralias 'danbooru-builder-directory 'danbooru-catalog-directory)

(defcustom danbooru-builder-output-dir nil
  "Directory for generated images.
nil means output_dir of config.json, relative to `danbooru-builder-directory'."
  :type '(choice (const :tag "From config.json" nil) directory))

(defcustom danbooru-builder-save-directory nil
  "Default directory for saved builder files (.dbb).
nil means presets/ under `danbooru-builder-directory'."
  :type '(choice (const :tag "presets/ of the tag directory" nil) directory))

(defface danbooru-builder-heading
  '((t :inherit font-lock-function-name-face :weight bold :height 1.1))
  "Scene and person headings.")

(defface danbooru-builder-category
  '((t :inherit font-lock-keyword-face))
  "Category names.")

(defface danbooru-builder-tag-text
  '((t :inherit shadow))
  "The prompt text of a tag whose label differs from it.")

(defface danbooru-builder-vary
  '((t :inherit font-lock-builtin-face :weight bold))
  "Variation lines.")

(defface danbooru-builder-off
  '((t :inherit shadow :strike-through t))
  "Alternatives that are switched off.")

(defface danbooru-builder-mark
  '((t :inherit warning))
  "Mark of a marked tag.")

(defface danbooru-builder-prompt
  '((t :inherit font-lock-string-face))
  "The generated prompt.")

;;; ── Constants (defaults of builder.py, overridable in config.json) ──

(defconst danbooru-builder--custom "custom"
  "Category of tags that are neither in the catalog nor typed vocabulary.")

(defconst danbooru-builder--scene-categories
  '("quality" "count" "series" "artist" "camera" "lighting" "background")
  "Categories whose tags belong to the whole image, never to one person.
config.json key: scene_categories.")

(defconst danbooru-builder--prompt-sections
  '(("quality") ("count") ("character") ("series") ("artist"))
  "Anima prompt sections in order; other categories are general tags.
config.json key: prompt_sections.")

(defconst danbooru-builder--ordered-categories '("quality")
  "Categories whose tags go into the prompt in catalog order.
config.json key: ordered_categories.")

(defconst danbooru-builder--vocab-type-category danbooru-catalog-type-categories
  "Vocabulary type categories from the shared catalog.")

(defconst danbooru-builder--person-types
  '(("girl" "girl" "girl") ("woman" "girl" "woman") ("boy" "boy" "boy")
    ("man" "boy" "man") ("other" "other" "person"))
  "(TYPE COUNT-KIND PROMPT-WORD) of a person.")

(defconst danbooru-builder--positions
  '(("no position" . "") ("left" . "on the left") ("right" . "on the right")
    ("up" . "on the up") ("down" . "on the down") ("center" . "in the center")
    ("foreground" . "in the foreground") ("background" . "in the background"))
  "Person positions: (NAME . PROMPT TEXT).")

(defconst danbooru-builder--score-re "\\`score_[0-9]+\\(?:_up\\)?\\'"
  "Score tags keep their underscores.")

(defconst danbooru-builder--weight-re ":[[:space:]]*-?[0-9.]+[[:space:]]*)"
  "Weight syntax such as (tag:1.2), whose parentheses are not escaped.")

(defconst danbooru-builder--count-re
  (concat "\\`\\(?:[0-9][+]?\\(?:girl\\|boy\\|other\\)s?\\|solo\\|solo focus"
          "\\|multiple \\(?:girls\\|boys\\|others\\)\\|no humans\\)\\'")
  "Subject count tags, which come from the persons once there are any.")

;;; ── Catalog ──

(cl-defstruct (danbooru-builder-item
               (:constructor danbooru-builder--make-item
                             (category group label tag &optional desc shared))
               (:copier nil))
  "One tag of the catalog or vocabulary."
  category group label tag desc shared)

(cl-defstruct (danbooru-builder-catalog
               (:constructor danbooru-builder--make-catalog)
               (:copier nil))
  "Everything read from `danbooru-builder-directory'."
  config      ; config.json as an alist with symbol keys
  categories  ; ((CATEGORY . ITEMS) ...) in catalog order, custom last
  candidates  ; completion candidates: catalog labels, then vocabulary
  lookup      ; candidate -> item
  shared)     ; shared vocabulary snapshot, separate from config

(defvar danbooru-builder--catalog nil "The loaded catalog.")

(defalias 'danbooru-builder--json-file #'danbooru-catalog-json-file)

(defun danbooru-builder--catalog-item (item)
  "Adapt shared ITEM to the legacy builder's prompt representation."
  (let* ((tag (danbooru-catalog-item-tag item))
         (shown (if (danbooru-catalog-item-vocabulary item)
                    (if (string-match-p danbooru-builder--score-re tag) tag
                      (string-replace "_" " " tag)) tag)))
    (danbooru-builder--make-item
     (danbooru-catalog-item-category item)
     (string-join (danbooru-catalog-item-path item) " / ")
     (if (danbooru-catalog-item-vocabulary item) shown (danbooru-catalog-item-label item))
     shown (danbooru-catalog-item-description item) item)))

(defun danbooru-builder--load-catalog (&optional shared)
  "Project SHARED vocabulary and separately loaded builder configuration."
  (let* ((shared (or shared (danbooru-catalog-get)))
         (file (expand-file-name "config.json" danbooru-builder-directory))
         (config (and (file-exists-p file)
                      (danbooru-builder--json-file file :object-type 'alist :array-type 'list
                                                  :null-object nil :false-object nil)))
         (order (alist-get 'category_order config))
         (lookup (make-hash-table :test #'equal)) table candidates)
    (dolist (record
             (append
              (seq-remove #'danbooru-catalog-item-vocabulary (danbooru-catalog-items shared))
              (sort (seq-filter
                     (lambda (item)
                       (and (danbooru-catalog-item-vocabulary item)
                            (eq item (gethash (danbooru-catalog-item-tag item)
                                              (danbooru-catalog-lookup shared)))))
                     (danbooru-catalog-items shared))
                    (lambda (a b) (> (danbooru-catalog-item-count a)
                                     (danbooru-catalog-item-count b))))))
      (let* ((item (danbooru-builder--catalog-item record))
             (category (danbooru-builder-item-category item))
             (label (danbooru-builder-item-label item))
             (cell (assoc category table))
             (candidate label))
        (unless cell (setq cell (list category)) (push cell table))
        ;; Vocabulary is available for completion without filling category views
        ;; with the entire CSV.  Hierarchical catalog order remains intact.
        (unless (danbooru-catalog-item-vocabulary record)
          (setcdr cell (append (cdr cell) (list item))))
        (when (gethash candidate lookup)
          (setq candidate (format "%s · %s" label category)))
        (when (gethash candidate lookup)
          (setq candidate (format "%s · %s" candidate (danbooru-catalog-item-id record))))
        (puthash candidate item lookup)
        (push candidate candidates)))
    (dolist (category (cons "custom" (mapcar #'cdr danbooru-builder--vocab-type-category)))
      (unless (assoc category table) (push (list category) table)))
    (let* ((names (delete "custom" (mapcar #'car table)))
           (ordered (append (seq-filter (lambda (c) (member c names)) order)
                            (sort (seq-remove (lambda (c) (member c order)) names) #'string<))))
      (danbooru-builder--make-catalog
       :shared shared :config config :lookup lookup :candidates (nreverse candidates)
       :categories (append (mapcar (lambda (c) (assoc c table)) ordered)
                           (list (assoc "custom" table)))))))

(defun danbooru-builder--catalog ()
  "Return a builder projection of the current shared vocabulary snapshot."
  (let ((shared (danbooru-catalog-get)))
    (unless (and danbooru-builder--catalog
                 (eq shared (danbooru-builder-catalog-shared danbooru-builder--catalog)))
      (setq danbooru-builder--catalog (danbooru-builder--load-catalog shared)))
    danbooru-builder--catalog))

(defun danbooru-builder--cfg (catalog key &optional default)
  "Value of KEY in the config of CATALOG, DEFAULT when absent."
  (let ((cell (assq key (danbooru-builder-catalog-config catalog))))
    (if cell (cdr cell) default)))

(defun danbooru-builder--category-items (catalog category)
  "Catalog items of CATEGORY."
  (cdr (assoc category (danbooru-builder-catalog-categories catalog))))

(defun danbooru-builder--item-for (catalog candidate)
  "The item a completion CANDIDATE stands for; free text becomes custom."
  (let* ((lookup (danbooru-builder-catalog-lookup catalog))
         (hit (or (gethash candidate lookup)
                  (gethash (string-replace "_" " " (downcase candidate)) lookup))))
    (cond
     ((danbooru-builder-item-p hit) hit)
     (hit
      (let* ((shown (if (string-match-p danbooru-builder--score-re (car hit))
                        (car hit)
                      (string-replace "_" " " (car hit))))
             (cat (or (alist-get (nth 1 hit) danbooru-builder--vocab-type-category)
                      danbooru-builder--custom)))
        (danbooru-builder--make-item cat "" shown shown)))
     (t (danbooru-builder--make-item danbooru-builder--custom "" candidate candidate)))))

;;; ── State ──

(cl-defstruct (danbooru-builder-alt
               (:constructor danbooru-builder--make-alt (label tag))
               (:copier nil))
  "One tag text: the label shown and the TAG text put in the prompt.
TAG may hold several comma separated tags.  OFF excludes an alternative."
  label tag off)

(cl-defstruct (danbooru-builder-entry
               (:constructor danbooru-builder--make-entry
                             (owner category alts &optional vary))
               (:copier nil))
  "A tag slot.  OWNER is a person id or nil for the scene.
A plain tag has one alt; a variation (VARY) has alternatives.
Variations with the same LINK name step together instead of combining."
  owner category alts vary link)

(cl-defstruct (danbooru-builder-person
               (:constructor danbooru-builder--make-person (id type position name))
               (:copier nil))
  "A person: TYPE from `danbooru-builder--person-types', POSITION text."
  id type position name)

(cl-defstruct (danbooru-builder-state
               (:constructor danbooru-builder--make-state)
               (:copier nil))
  "The prompt being built."
  catalog entries persons texts (style 'tags) (extra "") negative gen)

(cl-defstruct (danbooru-builder-text
               (:constructor danbooru-builder--make-text
                             (text &optional position category owner))
               (:copier nil))
  "Literal TEXT following the tags of OWNER in CATEGORY.
OWNER is a person id or nil for the scene.  POSITION is only used for
legacy blocks without a category; it counts preceding prompt parts."
  text position category owner)

(defun danbooru-builder--texts (state owner category)
  "Text blocks of OWNER in CATEGORY, in insertion order."
  (seq-filter (lambda (block)
                (and (equal (danbooru-builder-text-category block) category)
                     (eql (danbooru-builder-text-owner block) owner)))
              (danbooru-builder-state-texts state)))

(defun danbooru-builder--positional-texts (state)
  "Legacy text blocks of STATE that still use numbered positions."
  (seq-remove #'danbooru-builder-text-category
              (danbooru-builder-state-texts state)))

(defun danbooru-builder--scene-category-p (state category)
  "Non-nil when CATEGORY always belongs to the scene in STATE."
  (member category (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                                          'scene_categories
                                          danbooru-builder--scene-categories)))

(defun danbooru-builder--category-rank (state category)
  "Position of CATEGORY in the catalog; unknown categories rank as custom."
  (let ((names (mapcar #'car (danbooru-builder-catalog-categories
                              (danbooru-builder-state-catalog state)))))
    (or (cl-position category names :test #'equal)
        (cl-position danbooru-builder--custom names :test #'equal))))

(defun danbooru-builder--sections (state)
  "Prompt sections of STATE: a list of category lists."
  (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                         'prompt_sections danbooru-builder--prompt-sections))

(defun danbooru-builder--section-of (state category)
  "Index of the prompt section of CATEGORY; the section count = general tags."
  (let ((sections (danbooru-builder--sections state)))
    (or (cl-position-if (lambda (sec) (member category sec)) sections)
        (length sections))))

(defun danbooru-builder--display-key (state category)
  "Sort key of CATEGORY: prompt section, then catalog order."
  (cons (danbooru-builder--section-of state category)
        (danbooru-builder--category-rank state category)))

(defun danbooru-builder--key< (a b)
  "Compare display keys A and B."
  (or (< (car a) (car b))
      (and (= (car a) (car b)) (< (cdr a) (cdr b)))))

(defun danbooru-builder--entries (state owner category)
  "Entries of OWNER in CATEGORY in prompt order."
  (let ((entries (seq-filter (lambda (e)
                               (and (eql (danbooru-builder-entry-owner e) owner)
                                    (equal (danbooru-builder-entry-category e) category)))
                             (danbooru-builder-state-entries state))))
    (if (not (member category (danbooru-builder--cfg
                               (danbooru-builder-state-catalog state)
                               'ordered_categories
                               danbooru-builder--ordered-categories)))
        entries
      (let* ((items (danbooru-builder--category-items
                     (danbooru-builder-state-catalog state) category))
             (pos (lambda (e)
                    (or (cl-position (danbooru-builder-alt-tag
                                      (car (danbooru-builder-entry-alts e)))
                                     items :key #'danbooru-builder-item-tag
                                     :test #'equal)
                        (length items)))))
        (sort entries (lambda (a b) (< (funcall pos a) (funcall pos b))))))))

(defun danbooru-builder--owner-categories (state owner)
  "Categories OWNER has entries or text in, in display order."
  (sort (delete-dups
         (append
          (mapcar #'danbooru-builder-entry-category
                  (seq-filter (lambda (e) (eql (danbooru-builder-entry-owner e) owner))
                              (danbooru-builder-state-entries state)))
          (mapcar #'danbooru-builder-text-category
                  (seq-filter
                   (lambda (block)
                     (and (danbooru-builder-text-category block)
                          (eql (danbooru-builder-text-owner block) owner)))
                   (danbooru-builder-state-texts state)))))
        (lambda (a b)
          (danbooru-builder--key< (danbooru-builder--display-key state a)
                                  (danbooru-builder--display-key state b)))))

(defun danbooru-builder--find (state owner category tag)
  "The entry of OWNER in CATEGORY that has an alternative TAG."
  (seq-find (lambda (e)
              (and (eql (danbooru-builder-entry-owner e) owner)
                   (equal (danbooru-builder-entry-category e) category)
                   (seq-find (lambda (a) (equal (danbooru-builder-alt-tag a) tag))
                             (danbooru-builder-entry-alts e))))
            (danbooru-builder-state-entries state)))

(defun danbooru-builder--insert-entry (state entry &optional after)
  "Add ENTRY to STATE, right after entry AFTER when given."
  (let ((entries (danbooru-builder-state-entries state)))
    (setf (danbooru-builder-state-entries state)
          (if-let* ((tail (and after (memq after entries))))
              (append (seq-take entries (1+ (- (length entries) (length tail))))
                      (list entry) (cdr tail))
            (append entries (list entry))))))

(defun danbooru-builder--add (state owner item &optional after)
  "Add catalog ITEM for OWNER, after entry AFTER if it is in the same slot.
Scene categories go to the scene.  Return the new entry, or nil when
the tag was there already."
  (let* ((cat (danbooru-builder-item-category item))
         (owner (if (danbooru-builder--scene-category-p state cat) nil owner))
         (tag (danbooru-builder-item-tag item)))
    (unless (danbooru-builder--find state owner cat tag)
      (let ((entry (danbooru-builder--make-entry
                    owner cat (list (danbooru-builder--make-alt
                                     (danbooru-builder-item-label item) tag)))))
        (danbooru-builder--insert-entry
         state entry
         (and after (eql (danbooru-builder-entry-owner after) owner)
              (equal (danbooru-builder-entry-category after) cat)
              after))
        entry))))

(defun danbooru-builder--remove (state entry)
  "Remove ENTRY from STATE."
  (setf (danbooru-builder-state-entries state)
        (delq entry (danbooru-builder-state-entries state))))

(defun danbooru-builder--person (state id)
  "The person with ID in STATE."
  (seq-find (lambda (p) (eql (danbooru-builder-person-id p) id))
            (danbooru-builder-state-persons state)))

(defun danbooru-builder--person-name (state person)
  "Display name of PERSON."
  (let ((name (danbooru-builder-person-name person)))
    (if (and name (not (string-empty-p name)))
        name
      (format "Person %d" (1+ (cl-position person (danbooru-builder-state-persons state)))))))

(defun danbooru-builder--person-word (person)
  "Prompt word of PERSON (girl, woman, person, ...)."
  (or (nth 2 (assoc (danbooru-builder-person-type person) danbooru-builder--person-types))
      "person"))

(defun danbooru-builder--add-person (state type position name)
  "Add a person of TYPE at POSITION named NAME to STATE and return it.
The first person drops the scene's own count tags, which the persons now
provide."
  (unless (danbooru-builder-state-persons state)
    (let (removed)
      (dolist (e (danbooru-builder-state-entries state))
        (when (and (null (danbooru-builder-entry-owner e))
                   (seq-every-p
                    (lambda (a)
                      (seq-every-p (lambda (piece)
                                     (let ((case-fold-search nil))
                                       (string-match-p danbooru-builder--count-re
                                                       (string-replace "_" " " (string-trim piece)))))
                                   (split-string (danbooru-builder-alt-tag a) ",")))
                    (danbooru-builder-entry-alts e)))
          (push (danbooru-builder-alt-tag (car (danbooru-builder-entry-alts e))) removed)
          (danbooru-builder--remove state e)))
      (when removed
        (message "Removed %s, count tags now come from the persons"
                 (string-join (nreverse removed) ", ")))))
  (let ((person (danbooru-builder--make-person
                 (1+ (apply #'max 0 (mapcar #'danbooru-builder-person-id
                                            (danbooru-builder-state-persons state))))
                 type position name)))
    (setf (danbooru-builder-state-persons state)
          (append (danbooru-builder-state-persons state) (list person)))
    person))

(defun danbooru-builder--remove-person (state person)
  "Remove PERSON and their tags and text from STATE."
  (let ((id (danbooru-builder-person-id person)))
    (setf (danbooru-builder-state-entries state)
          (seq-remove (lambda (e) (eql (danbooru-builder-entry-owner e) id))
                      (danbooru-builder-state-entries state))
          (danbooru-builder-state-texts state)
          (seq-remove (lambda (block) (eql (danbooru-builder-text-owner block) id))
                      (danbooru-builder-state-texts state))
          (danbooru-builder-state-persons state)
          (delq person (danbooru-builder-state-persons state)))))

;;; ── Generation settings ──

(defun danbooru-builder--profiles (state)
  "Profile names of STATE's config."
  (mapcar (lambda (p) (symbol-name (car p)))
          (danbooru-builder--cfg (danbooru-builder-state-catalog state) 'profiles)))

(defun danbooru-builder--apply-profile (state name)
  "Use profile NAME: its default size, steps, cfg, sampler, scheduler, style."
  (let* ((prof (alist-get (intern name) (danbooru-builder--cfg
                                         (danbooru-builder-state-catalog state)
                                         'profiles)))
         (d (alist-get 'defaults prof))
         (args (alist-get 'args prof))
         (style (alist-get 'prompt_style prof))
         (server (alist-get 'server_url prof))
         (gen (danbooru-builder-state-gen state)))
    (setf (danbooru-builder-state-style state)
          (cond (style (if (equal style "natural") 'natural 'tags))
                ((or (member "--t5xxl" args) (member "--llm" args)) 'natural)
                (t 'tags)))
    (setf (danbooru-builder-state-gen state)
          (list :profile name
                :width (alist-get 'width d 1024) :height (alist-get 'height d 1024)
                :steps (alist-get 'steps d 30) :cfg (alist-get 'cfg d 6.0)
                :sampler (alist-get 'sampler d "euler_a")
                :scheduler (alist-get 'scheduler d "karras")
                :seed (or (plist-get gen :seed) -1)
                :seed-end (or (plist-get gen :seed-end) -1)
                :seed-step (or (plist-get gen :seed-step) 1)
                :backend (if (and server (not (string-blank-p server)))
                             (string-trim server)
                           (or (plist-get gen :backend)
                               (danbooru-builder--default-backend
                                (danbooru-builder-state-catalog state))))))))

(defun danbooru-builder--default-backend (catalog)
  "server_url of CATALOG's config, or \"sd-cli\" when it is empty."
  (let ((url (danbooru-builder--cfg catalog 'server_url "")))
    (if (string-blank-p (or url "")) "sd-cli" (string-trim url))))

(defun danbooru-builder--new-state (catalog)
  "A fresh state over CATALOG with the config's defaults."
  (let ((state (danbooru-builder--make-state :catalog catalog)))
    (setf (danbooru-builder-state-negative state)
          (danbooru-builder--cfg catalog 'negative_prompt ""))
    (if-let* ((profile (car (danbooru-builder--profiles state))))
        (danbooru-builder--apply-profile state profile)
      (setf (danbooru-builder-state-gen state)
            (list :width 1024 :height 1024 :steps 30 :cfg 6.0 :sampler "euler_a"
                  :scheduler "karras" :seed -1 :seed-end -1 :seed-step 1
                  :backend (danbooru-builder--default-backend catalog))))
    (pcase-dolist (`(,cat . ,tags) (danbooru-builder--cfg catalog 'default_selection))
      (dolist (tag tags)
        (danbooru-builder--add state nil (danbooru-builder--make-item
                                          (symbol-name cat) "" tag tag))))
    state))

(defun danbooru-builder--seeds (state)
  "Seeds of one batch; a random start seed gives one random seed."
  (let* ((gen (danbooru-builder-state-gen state))
         (start (plist-get gen :seed))
         (end (plist-get gen :seed-end))
         (step (max 1 (or (plist-get gen :seed-step) 1))))
    (cond ((< start 0) (list (random 2147483647)))
          ((< end start) (list start))
          (t (number-sequence start end step)))))

(defun danbooru-builder--seed-count (state)
  "Number of seeds in one batch."
  (let* ((gen (danbooru-builder-state-gen state))
         (start (plist-get gen :seed))
         (end (plist-get gen :seed-end))
         (step (max 1 (or (plist-get gen :seed-step) 1))))
    (if (<= 0 start end) (1+ (/ (- end start) step)) 1)))

;;; ── Variations ──

(defun danbooru-builder--active-alts (entry)
  "Alternatives of ENTRY that are not switched off."
  (seq-remove #'danbooru-builder-alt-off (danbooru-builder-entry-alts entry)))

(defun danbooru-builder--axes (state)
  "((ENTRY . ACTIVE-ALTS) ...) for every variation, in prompt order."
  (let ((entries (danbooru-builder-state-entries state)))
    (cl-loop for e in (sort (seq-filter #'danbooru-builder-entry-vary entries)
                            (lambda (a b)
                              (danbooru-builder--key<
                               (danbooru-builder--display-key
                                state (danbooru-builder-entry-category a))
                               (danbooru-builder--display-key
                                state (danbooru-builder-entry-category b)))))
             for alts = (danbooru-builder--active-alts e)
             when alts collect (cons e alts))))

(defun danbooru-builder--groups (state)
  "The independent ways the prompt varies, in prompt order.
Each group is a list of steps, each step a list of (ENTRY . ALT).  An
unlinked variation is a group of its own; linked variations form one
group whose step N takes alternative N of each, as many steps as the
shortest of them has."
  (let ((axes (danbooru-builder--axes state))
        groups done)
    (dolist (axis axes)
      (let ((link (danbooru-builder-entry-link (car axis))))
        (cond
         ((null link)
          (push (mapcar (lambda (alt) (list (cons (car axis) alt))) (cdr axis)) groups))
         ((member link done))
         (t
          (push link done)
          (let* ((linked (seq-filter (lambda (a) (equal (danbooru-builder-entry-link (car a)) link))
                                     axes))
                 (n (apply #'min (mapcar (lambda (a) (length (cdr a))) linked))))
            (push (cl-loop for i below n
                           collect (mapcar (lambda (a) (cons (car a) (nth i (cdr a)))) linked))
                  groups))))))
    (nreverse groups)))

(defun danbooru-builder--link-steps (state link)
  "Number of steps of the linked variations named LINK."
  (let ((lens (cl-loop for (e . alts) in (danbooru-builder--axes state)
                       when (equal (danbooru-builder-entry-link e) link)
                       collect (length alts))))
    (if lens (apply #'min lens) 0)))

(defun danbooru-builder--variants (state)
  "Every combination of the variations: a list of picks ((ENTRY . ALT) ...).
The last group changes fastest.  No variations gives one empty pick."
  (let ((result (list nil)))
    (dolist (group (reverse (danbooru-builder--groups state)))
      (setq result (cl-loop for step in group
                            nconc (mapcar (lambda (r) (append step r)) result))))
    result))

(defun danbooru-builder--variant-count (state)
  "Number of prompt variants."
  (cl-reduce #'* (mapcar #'length (danbooru-builder--groups state)) :initial-value 1))

(defun danbooru-builder--batch-size (state)
  "Number of images one generate makes."
  (* (danbooru-builder--variant-count state) (danbooru-builder--seed-count state)))

;;; ── Prompt ──

(defun danbooru-builder--format-tag (state tag category)
  "TAG as written in the prompt, for CATEGORY."
  (let ((tag (string-trim tag))
        (case-fold-search nil))
    (when (and (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                                      'underscores_to_spaces t)
               (> (length tag) 3) (string-search "_" tag) (not (string-search " " tag))
               (not (string-match-p danbooru-builder--score-re tag)))
      (setq tag (string-replace "_" " " tag)))
    (when (and (equal category "artist") (not (string-empty-p tag))
               (not (string-prefix-p "@" tag)))
      (setq tag (concat "@" tag)))   ; Anima: artists are weak without the @
    ;; Danbooru qualifiers like "saber (fate)" need escaping, weights don't
    (when (and (string-search "(" tag) (not (string-search "\\(" tag))
               (not (string-match-p danbooru-builder--weight-re tag)))
      (setq tag (replace-regexp-in-string "[()]" "\\\\\\&" tag)))
    tag))

(defun danbooru-builder--chosen (entry pick)
  "The alternative of ENTRY used in variant PICK, or nil."
  (if (danbooru-builder-entry-vary entry)
      (cdr (assq entry pick))
    (car (danbooru-builder-entry-alts entry))))

(defvar danbooru-builder--raw-alts nil
  "Alternatives whose text goes into the prompt as is: export placeholders.")

(defun danbooru-builder--collect (state pick owner section)
  "Prompt parts of OWNER in SECTION for PICK, with text after each category.
Tags are deduplicated; literal text blocks retain spelling and repetition."
  (let (out seen)
    (dolist (cat (danbooru-builder--owner-categories state owner))
      (when (= (danbooru-builder--section-of state cat) section)
        (dolist (entry (danbooru-builder--entries state owner cat))
          (when-let* ((alt (danbooru-builder--chosen entry pick)))
            (dolist (piece (if (memq alt danbooru-builder--raw-alts)
                               (list (danbooru-builder-alt-tag alt))
                             (split-string (danbooru-builder-alt-tag alt) ",")))
              (let ((tag (if (memq alt danbooru-builder--raw-alts)
                             piece
                           (danbooru-builder--format-tag state piece cat))))
                (unless (or (string-empty-p tag) (member (downcase tag) seen))
                  (push (downcase tag) seen)
                  (push tag out))))))
        (dolist (block (danbooru-builder--texts state owner cat))
          ;; Preserve literals through section deduplication and name casing.
          (push (propertize (danbooru-builder-text-text block)
                            'danbooru-builder-literal t)
                out))))
    (nreverse out)))

(defun danbooru-builder--count-tags (state)
  "1girl, 2boys, ... for the persons of STATE."
  (let (counts)
    (dolist (p (danbooru-builder-state-persons state))
      (let ((kind (or (nth 1 (assoc (danbooru-builder-person-type p)
                                    danbooru-builder--person-types))
                      "other")))
        (cl-incf (alist-get kind counts 0 nil #'equal))))
    (cl-loop for kind in '("girl" "boy" "other")
             for n = (alist-get kind counts 0 nil #'equal)
             unless (zerop n)
             collect (if (= n 1)
                         (concat "1" kind)
                       (format "%d%s%ss" (min n 6) (if (>= n 6) "+" "") kind)))))

(defun danbooru-builder--uniq (tags)
  "TAGS without case-insensitive duplicates, preserving literal text."
  (let (seen out)
    (dolist (tag tags)
      (unless (and (not (get-text-property 0 'danbooru-builder-literal tag))
                   (member (downcase tag) seen))
        (unless (get-text-property 0 'danbooru-builder-literal tag)
          (push (downcase tag) seen))
        (push tag out)))
    (nreverse out)))

(defun danbooru-builder--name-case (tag)
  "\"hatsune miku\" -> \"Hatsune Miku\"; a trailing \\(series\\) is kept."
  (let* ((i (string-search " \\(" tag))
         (name (if i (substring tag 0 i) tag)))
    (if (or (get-text-property 0 'danbooru-builder-literal tag)
            (string-prefix-p "(" name) (string-prefix-p "@" name))
        tag
      (concat (mapconcat (lambda (w)
                           (if (string-empty-p w) w
                             (concat (upcase (substring w 0 1)) (substring w 1))))
                         (split-string name " ")
                         " ")
              (if i (substring tag i) "")))))

(defun danbooru-builder--build-prompt (state &optional pick)
  "The prompt of STATE for variant PICK (default: the first variant).
Anima order: quality, count, character, series, @artist, general tags."
  (pcase-let ((`(,separator . ,parts) (danbooru-builder--prompt-parts state pick)))
    (string-join parts separator)))

(defun danbooru-builder--prompt-parts (state &optional pick)
  "The prompt of STATE for variant PICK as (SEPARATOR . PARTS).
Free-form text is interleaved with the generated prompt parts verbatim."
  (pcase-let ((`(,separator . ,layout) (danbooru-builder--prompt-layout state pick)))
    (cons separator (mapcar (lambda (part)
                             (substring-no-properties
                              (if (danbooru-builder-text-p part)
                                  (danbooru-builder-text-text part)
                                part)))
                           layout))))

(defun danbooru-builder--prompt-layout (state &optional pick)
  "Prompt parts and text blocks of STATE for PICK as (SEPARATOR . LAYOUT)."
  (pcase-let* ((`(,separator . ,parts) (danbooru-builder--base-prompt-parts state pick))
               (count (length parts))
               (texts (cl-stable-sort (danbooru-builder--positional-texts state)
                                      #'< :key #'danbooru-builder-text-position))
               (position 0)
               (layout nil))
    (while (or parts texts)
      (if (and texts (<= (min count (danbooru-builder-text-position (car texts)))
                         position))
          (push (pop texts) layout)
        (push (pop parts) layout)
        (cl-incf position)))
    (cons separator (nreverse layout))))

(defun danbooru-builder--base-prompt-parts (state &optional pick)
  "The prompt of STATE for variant PICK as (SEPARATOR . PARTS).
Joining PARTS with SEPARATOR gives the prompt before legacy positional text.
In tags style each tag is a part; natural style uses sentences."
  (let* ((pick (or pick (car (danbooru-builder--variants state))))
         (n (length (danbooru-builder--sections state)))
         (general n)
         (char-sec (danbooru-builder--section-of state "character"))
         (count-sec (danbooru-builder--section-of state "count"))
         (persons (danbooru-builder-state-persons state))
         (extra (string-trim (string-trim (or (danbooru-builder-state-extra state) ""))
                             ",+" ",+"))
         (extra (unless (string-empty-p extra) (list extra))))
    (cl-flet ((ct (owner i) (danbooru-builder--collect state pick owner i))
              (pos (p) (or (danbooru-builder-person-position p) "")))
      (if (null persons)
          (cons ", " (append (cl-loop for i from 0 to n append (ct nil i)) extra))
        (let ((ids (mapcar #'danbooru-builder-person-id persons)))
          (cl-flet ((section (i)
                      (danbooru-builder--uniq
                       (append (and (= i count-sec) (danbooru-builder--count-tags state))
                               (cl-loop for id in (append ids (list nil))
                                        append (ct id i))))))
            (if (eq (danbooru-builder-state-style state) 'natural)
                ;; section tags lead, each person is introduced by their
                ;; character name and described, scene general tags close it
                (let* ((head (append (cl-loop for i below n unless (= i char-sec)
                                              append (section i))
                                     (mapcar #'danbooru-builder--name-case
                                             (ct nil char-sec))))
                       (out (and head (list (concat (string-join (danbooru-builder--uniq head) ", ")
                                                    ".")))))
                  (dolist (p persons)
                    (let* ((word (danbooru-builder--person-word p))
                           (names (mapcar #'danbooru-builder--name-case
                                          (ct (danbooru-builder-person-id p) char-sec)))
                           (tags (ct (danbooru-builder-person-id p) general))
                           (intro (concat (if (string-empty-p (pos p))
                                              (format "a %s" word)
                                            (format "%s, a %s" (pos p) word))
                                          (mapconcat (lambda (nm) (concat ", " nm)) names ""))))
                      (push (concat (upcase (substring intro 0 1)) (substring intro 1)
                                    (if tags (concat ": " (string-join tags ", ")) "")
                                    ".")
                            out)))
                  (when-let* ((scene (ct nil general)))
                    (push (concat "Scene: " (string-join scene ", ") ".") out))
                  (cons " " (append (nreverse out) extra)))
              (let ((blocks (cl-mapcan (lambda (p)
					 (append (unless (string-empty-p (pos p))
                                                   (list (format "%s %s"
								 (danbooru-builder--person-word p)
								 (pos p))))
						 (ct (danbooru-builder-person-id p) general)))
                                       persons)))
                (cons ", " (seq-remove #'string-empty-p
                                       (append (cl-loop for i below n append (section i))
                                               blocks
                                               (ct nil general)
                                               extra)))))))))))

(defun danbooru-builder--token-estimate (prompt)
  "Rough CLIP token count of PROMPT: 1.3 per word plus commas."
  (let ((words 0) (commas 0) (start 0))
    (while (string-match "\\w+" prompt start)
      (cl-incf words)
      (setq start (match-end 0)))
    (setq start 0)
    (while (string-match "," prompt start)
      (cl-incf commas)
      (setq start (match-end 0)))
    (truncate (+ (* words 1.3) commas))))

;;; ── Buffer ──

(defvar-local danbooru-builder--state nil "State of this builder buffer.")
(defvar-local danbooru-builder--marked nil "Marked entries.")
(defvar-local danbooru-builder--file nil "File the builder was saved to or loaded from.")
(defvar-local danbooru-builder--saved nil
  "The state as last saved or loaded, serialized; compared to find changes.")

(defun danbooru-builder--st ()
  "The state of the current builder buffer."
  (or danbooru-builder--state (user-error "Not in a danbooru builder buffer")))

(defun danbooru-builder--prop (prop)
  "Text property PROP of the current line."
  (get-text-property (line-beginning-position) prop))

(defun danbooru-builder--owner-at-point ()
  "Person id of the section at point, nil for the scene."
  (let ((section (danbooru-builder--prop 'danbooru-builder-section)))
    (and (danbooru-builder-person-p section) (danbooru-builder-person-id section))))

(defun danbooru-builder--insert-line (props &rest strings)
  "Insert STRINGS and a newline, giving the whole line text properties PROPS."
  (let ((start (point)))
    (apply #'insert strings)
    (insert "\n")
    (add-text-properties start (point) props)))

(defun danbooru-builder--alt-text (alt)
  "Label of ALT, followed by its prompt text when that differs."
  (let ((label (danbooru-builder-alt-label alt))
        (tag (danbooru-builder-alt-tag alt)))
    (if (equal label tag)
        label
      (concat label (propertize (concat "  → " tag) 'face 'danbooru-builder-tag-text)))))

(defun danbooru-builder--insert-section (state person)
  "Insert the heading and tags of PERSON, or of the scene when PERSON is nil."
  (let* ((owner (and person (danbooru-builder-person-id person)))
         (section (or person 'scene))
         (props (list 'danbooru-builder-section section))
         (cats (danbooru-builder--owner-categories state owner)))
    (danbooru-builder--insert-line
     props
     (propertize (if person
                     (concat (danbooru-builder--person-name state person) " — "
                             (danbooru-builder-person-type person)
                             (let ((pos (danbooru-builder-person-position person)))
                               (if (string-empty-p pos) "" (concat ", " pos))))
                   "Scene")
                 'face 'danbooru-builder-heading))
    (unless cats
      (danbooru-builder--insert-line
       props (propertize "    (no tags; a adds some)" 'face 'shadow)))
    (dolist (cat cats)
      (let ((first t))
        (dolist (entry (danbooru-builder--entries state owner cat))
          (let ((col (propertize (format "%-13s" (if first cat ""))
                                 'face 'danbooru-builder-category))
                (mark (if (memq entry danbooru-builder--marked)
                          (propertize "*" 'face 'danbooru-builder-mark)
                        " "))
                (eprops (append props (list 'danbooru-builder-entry entry
                                            'danbooru-builder-category cat))))
            (setq first nil)
            (if (not (danbooru-builder-entry-vary entry))
                (danbooru-builder--insert-line
                 eprops mark " " col " "
                 (danbooru-builder--alt-text (car (danbooru-builder-entry-alts entry))))
              (danbooru-builder--insert-line
               eprops mark " " col " "
               (propertize (format "◆ vary ×%d"
                                   (length (danbooru-builder--active-alts entry)))
                           'face 'danbooru-builder-vary)
               (if-let* ((link (danbooru-builder-entry-link entry)))
                   (let ((steps (danbooru-builder--link-steps state link))
                         (n (length (danbooru-builder--active-alts entry))))
                     (propertize (concat "  linked: " link
                                         (if (> n steps) (format " (%d unused)" (- n steps)) ""))
                                 'face 'danbooru-builder-tag-text))
                 ""))
              (dolist (alt (danbooru-builder-entry-alts entry))
                (danbooru-builder--insert-line
                 (append eprops (list 'danbooru-builder-alt alt))
                 (make-string 18 ?\s)
                 (if (danbooru-builder-alt-off alt)
                     (concat "✗ " (propertize (danbooru-builder-alt-label alt)
                                              'face 'danbooru-builder-off))
                   (concat "▸ " (danbooru-builder--alt-text alt))))))))
        (dolist (block (danbooru-builder--texts state owner cat))
          (danbooru-builder--insert-line
           (append props (list 'danbooru-builder-text block
                               'danbooru-builder-category cat))
           "  " (propertize (format "%-13s" (if first cat ""))
                            'face 'danbooru-builder-category)
           " " (propertize (concat "text: " (danbooru-builder-text-text block))
                           'face 'danbooru-builder-prompt))
          (setq first nil))))))

(defun danbooru-builder--location ()
  "What point is on: (ALT ENTRY SECTION LINE TEXT)."
  (list (danbooru-builder--prop 'danbooru-builder-alt)
        (danbooru-builder--prop 'danbooru-builder-entry)
        (danbooru-builder--prop 'danbooru-builder-section)
        (line-number-at-pos)
        (danbooru-builder--prop 'danbooru-builder-text)))

(defun danbooru-builder--goto-prop (prop value)
  "Move to the first line whose PROP is VALUE; return non-nil if found."
  (when-let* ((value value)
              (match (save-excursion
                       (goto-char (point-min))
                       (text-property-search-forward prop value #'eq))))
    (goto-char (prop-match-beginning match))
    t))

(defun danbooru-builder--restore (location)
  "Move back to LOCATION from `danbooru-builder--location'."
  (pcase-let ((`(,alt ,entry ,section ,line ,text) location))
    (goto-char (point-min))
    (or (danbooru-builder--goto-prop 'danbooru-builder-text text)
        (danbooru-builder--goto-prop 'danbooru-builder-alt alt)
        (danbooru-builder--goto-prop 'danbooru-builder-entry entry)
        ;; the thing at point is gone: stay on the same line if it is
        ;; still in the same section, else go to the section
        (progn (forward-line (1- line))
               (or (eq (danbooru-builder--prop 'danbooru-builder-section) section)
                   (danbooru-builder--goto-prop 'danbooru-builder-section section)
                   (goto-char (point-min)))))))

(defun danbooru-builder--render ()
  "Redraw the builder buffer from its state, keeping point on the same thing."
  (let* ((state (danbooru-builder--st))
         (location (danbooru-builder--location))
         (starts (mapcar (lambda (w) (cons w (window-start w)))
                         (get-buffer-window-list nil nil t)))
         (inhibit-read-only t))
    (setq danbooru-builder--marked
          (seq-filter (lambda (e) (memq e (danbooru-builder-state-entries state)))
                      danbooru-builder--marked))
    (erase-buffer)
    (danbooru-builder--insert-section state nil)
    (dolist (person (danbooru-builder-state-persons state))
      (insert "\n")
      (danbooru-builder--insert-section state person))
    (let* ((prompt (danbooru-builder--build-prompt state))
           (variants (danbooru-builder--variant-count state))
           (extra (danbooru-builder-state-extra state)))
      (insert "\n" (propertize (make-string 60 ?─) 'face 'shadow) "\n")
      (when (danbooru-builder--positional-texts state)
        (danbooru-builder--insert-layout state))
      (unless (string-empty-p (or extra ""))
        (insert (propertize "extra: " 'face 'shadow) extra "\n"))
      (insert (propertize prompt 'face 'danbooru-builder-prompt) "\n"
              (propertize (format "%d tags · ~%d tokens%s"
                                  (length (seq-remove #'string-blank-p
                                                      (split-string prompt ",")))
                                  (danbooru-builder--token-estimate prompt)
                                  (if (> variants 1)
                                      (format " · first of %d variants" variants)
                                    ""))
                          'face 'shadow)
              "\n"))
    (danbooru-builder--restore location)
    (pcase-dolist (`(,w . ,start) starts)
      (set-window-start w (min start (point-max)) t))
    (set-buffer-modified-p (danbooru-builder--modified-p))
    (force-mode-line-update)))

(defun danbooru-builder--insert-layout (state)
  "Show STATE's text blocks among the prompt parts they accompany."
  (let ((print-escape-newlines t)
        (props '(danbooru-builder-section prompt-order))
        (position 0))
    (danbooru-builder--insert-line
     props (propertize "Legacy prompt order — RET edit, t move to category, M-↑/↓ move"
                       'face 'danbooru-builder-heading))
    (dolist (part (cdr (danbooru-builder--prompt-layout state)))
      (if (danbooru-builder-text-p part)
          (danbooru-builder--insert-line
           (append props (list 'danbooru-builder-text part
                               'danbooru-builder-position position))
           "  text  " (propertize (prin1-to-string (danbooru-builder-text-text part))
                                  'face 'danbooru-builder-prompt))
        (cl-incf position)
        (danbooru-builder--insert-line
         (append props (list 'danbooru-builder-position position))
         "        " (propertize (replace-regexp-in-string "\n" " ↵ " part)
                               'face 'shadow))))
    (insert "\n")))

(defun danbooru-builder--header-line ()
  "Header line: model settings and batch size."
  (when-let* ((state danbooru-builder--state))
    (let* ((gen (danbooru-builder-state-gen state))
           (seed (plist-get gen :seed))
           (end (plist-get gen :seed-end))
           (n (danbooru-builder--batch-size state)))
      (concat
       " "
       (propertize (if danbooru-builder--file
                       (file-name-nondirectory danbooru-builder--file)
                     "unsaved")
                   'face 'bold)
       (if (buffer-modified-p) "*" "")
       " · "
       (string-join
        (delq nil
              (list (plist-get gen :profile)
                    (format "%d×%d" (plist-get gen :width) (plist-get gen :height))
                    (format "%s steps" (plist-get gen :steps))
                    (format "cfg %s" (plist-get gen :cfg))
                    (format "%s/%s" (plist-get gen :sampler) (plist-get gen :scheduler))
                    (cond ((< seed 0) "random seed")
                          ((> end seed) (format "seed %d..%d/%d" seed end
                                                (plist-get gen :seed-step)))
                          (t (format "seed %d" seed)))
                    (symbol-name (danbooru-builder-state-style state))
                    (let ((backend (plist-get gen :backend)))
                      (unless (equal backend "sd-cli") (concat "via " backend)))))
        " · ")
       (if (> n 1) (format "  ⇒ %d images" n) "")))))

;;; ── Completion ──

(defun danbooru-builder--annotate-item (item)
  "Completion annotation for ITEM."
  (let ((label (danbooru-builder-item-label item))
        (tag (danbooru-builder-item-tag item))
        (group (danbooru-builder-item-group item))
        (desc (danbooru-builder-item-desc item)))
    (concat (if (equal label tag) "" (concat "  → " tag))
            "  " (danbooru-builder-item-category item)
            (if (string-empty-p group) "" (concat " / " group))
            (let ((shared (danbooru-builder-item-shared item)))
              (if (and shared (danbooru-catalog-item-vocabulary shared))
                  (concat " " (danbooru-builder--format-count (danbooru-catalog-item-count shared)))
                ""))
            (if desc (concat " · " desc) ""))))

(defun danbooru-builder--format-count (n)
  "Post count N as 1.2M, 34k or 567."
  (cond ((>= n 1000000) (format "%.1fM" (/ n 1000000.0)))
        ((>= n 1000) (format "%dk" (round n 1000)))
        ((> n 0) (number-to-string n))
        (t "")))

(defun danbooru-builder--table (catalog candidates &optional lookup)
  "Completion table over CANDIDATES of CATALOG, annotated from LOOKUP."
  (let ((lookup (or lookup (danbooru-builder-catalog-lookup catalog))))
    (lambda (string pred action)
      (if (eq action 'metadata)
          `(metadata
            (category . danbooru-tag)
            (display-sort-function . identity)
            (cycle-sort-function . identity)
            (annotation-function
             . ,(lambda (cand)
                  (let ((hit (gethash cand lookup)))
                    (propertize
                     (cond ((danbooru-builder-item-p hit)
                            (danbooru-builder--annotate-item hit))
                           (hit
                            (format "  %s %s"
                                    (or (alist-get (nth 1 hit)
                                                   danbooru-builder--vocab-type-category)
                                        "tag")
                                    (danbooru-builder--format-count (nth 2 hit))))
                           (t ""))
                     'face 'completions-annotations))))
            (group-function
             . ,(lambda (cand transform)
                  (if transform
                      cand
                    (let ((hit (gethash cand lookup)))
                      (if (danbooru-builder-item-p hit)
                          (let ((g (danbooru-builder-item-group hit)))
                            (concat (danbooru-builder-item-category hit)
                                    (if (string-empty-p g) "" (concat " / " g))))
                        "Danbooru vocabulary"))))))
        (complete-with-action action candidates string pred)))))

(declare-function icomplete-force-complete "icomplete" ())

(defvar-keymap danbooru-builder--tags-minibuffer-map
  :doc "Extra keys while reading tags with fido/icomplete."
  "TAB" #'icomplete-force-complete)

(defun danbooru-builder--crm (prompt table)
  "Read comma separated tags from TABLE with PROMPT.
With fido/icomplete, TAB completes the tag at point in place (by default
it would only list completions), so tags can be completed one by one:
stan TAB , sei TAB RET."
  (let ((crm-separator "[ \t]*,[ \t]*"))
    (minibuffer-with-setup-hook
        (:append (lambda ()
                   (when (bound-and-true-p icomplete-mode)
                     (use-local-map (make-composed-keymap
                                     danbooru-builder--tags-minibuffer-map
                                     (current-local-map))))))
      (completing-read-multiple prompt table))))

(defun danbooru-builder--confirm-custom (strings)
  "Ask before using STRINGS, which match no known tag, as custom tags.
Return the strings to keep."
  (if (or (null strings)
          (y-or-n-p (format "Not in the catalog or vocabulary: %s.  Add as custom tag%s? "
                            (string-join strings ", ") (if (cdr strings) "s" ""))))
      strings
    (message "Skipped %s" (string-join strings ", "))
    nil))

(defun danbooru-builder--read-items (prompt &optional category)
  "Read tags with completion, PROMPT first; return items.
With CATEGORY offer its catalog tags and file everything into it.
Text matching no known tag is added as a custom tag after asking."
  (let* ((catalog (danbooru-builder--catalog))
         (global (danbooru-builder-catalog-lookup catalog))
         (known (lambda (lookup s)
                  (or (gethash s lookup)
                      (gethash (string-replace "_" " " (downcase s)) lookup)))))
    (if (not category)
        (let* ((strings (danbooru-builder--crm
                         prompt (danbooru-builder--table
                                 catalog (danbooru-builder-catalog-candidates catalog))))
               (custom (danbooru-builder--confirm-custom
                        (seq-remove (lambda (s) (funcall known global s)) strings))))
          (mapcar (lambda (s) (danbooru-builder--item-for catalog s))
                  (seq-filter (lambda (s) (or (funcall known global s) (member s custom)))
                              strings)))
      (let ((lookup (make-hash-table :test #'equal))
            cands)
        (dolist (item (danbooru-builder--category-items catalog category))
          (let ((cand (danbooru-builder-item-label item)))
            (when (gethash cand lookup)
              (setq cand (format "%s · %s" cand (danbooru-builder-item-group item))))
            (unless (gethash cand lookup)
              (puthash cand item lookup)
              (push cand cands))))
        (let* ((strings (danbooru-builder--crm
                         prompt (danbooru-builder--table catalog (nreverse cands) lookup)))
               (custom (danbooru-builder--confirm-custom
                        (seq-remove (lambda (s) (or (funcall known lookup s)
                                                    (funcall known global s)))
                                    strings))))
          (delq nil
                (mapcar (lambda (s)
                          (cond
                           ((gethash s lookup))
                           ((or (funcall known global s) (member s custom))
                            ;; another category's tag or free text: file it here
                            (let ((item (danbooru-builder--item-for catalog s)))
                              (danbooru-builder--make-item
                               category "" (danbooru-builder-item-label item)
                               (danbooru-builder-item-tag item))))))
                        strings)))))))

(defun danbooru-builder--read-category (&optional default)
  "Read a category name, DEFAULT preselected."
  (let* ((state (danbooru-builder--st))
         (names (mapcar #'car (danbooru-builder-catalog-categories
                               (danbooru-builder-state-catalog state)))))
    (completing-read (format-prompt "Category" default) names nil t nil nil default)))

(defun danbooru-builder--owner-label (state owner)
  "Name of OWNER for prompts."
  (if owner (danbooru-builder--person-name state (danbooru-builder--person state owner))
    "Scene"))

;;; ── Commands ──

(defun danbooru-builder-add-text (text category &optional owner)
  "Add literal TEXT after the tags of OWNER in CATEGORY.
Interactively use the category and person at point; outside a category,
ask for one.  Scene categories always belong to the scene."
  (interactive
   (let* ((category (or (danbooru-builder--prop 'danbooru-builder-category)
                        (danbooru-builder--read-category)))
          (text (read-string "Free-form text: ")))
     (list text category (danbooru-builder--owner-at-point))))
  (unless (and (stringp text) (not (string-blank-p text))
               (stringp category) (not (string-blank-p category)))
    (user-error "Text and category must be nonempty"))
  (let* ((state (danbooru-builder--st))
         (owner (unless (danbooru-builder--scene-category-p state category) owner))
         (block (danbooru-builder--make-text text nil category owner)))
    (setf (danbooru-builder-state-texts state)
          (append (danbooru-builder-state-texts state) (list block)))
    (danbooru-builder--render)
    (danbooru-builder--goto-prop 'danbooru-builder-text block)))

(defun danbooru-builder-place-text ()
  "Choose a category for the free-form text at point."
  (interactive)
  (let* ((state (danbooru-builder--st))
         (block (or (danbooru-builder--prop 'danbooru-builder-text)
                    (user-error "No free-form text here"))))
    (let ((category (danbooru-builder--read-category
                     (danbooru-builder-text-category block))))
      (setf (danbooru-builder-text-category block) category
            (danbooru-builder-text-position block) nil
            (danbooru-builder-text-owner block)
            (unless (danbooru-builder--scene-category-p state category)
              (danbooru-builder-text-owner block))))
    (danbooru-builder--render)))

(defun danbooru-builder--move-text (state block dir)
  "Move BLOCK among sibling text blocks by DIR (-1 or 1).
Legacy positional blocks move through the prompt layout."
  (if (danbooru-builder-text-category block)
      (let* ((siblings (danbooru-builder--texts
                        state (danbooru-builder-text-owner block)
                        (danbooru-builder-text-category block)))
             (i (+ (cl-position block siblings :test #'eq) dir))
             (other (and (>= i 0) (nth i siblings))))
        (when other
          (setf (danbooru-builder-state-texts state)
                (danbooru-builder--swap (danbooru-builder-state-texts state) block other))))
    (let* ((layout (cdr (danbooru-builder--prompt-layout state)))
           (i (+ (cl-position block layout :test #'eq) dir))
           (other (and (>= i 0) (nth i layout)))
           (position 0)
           texts)
      (when other
        (dolist (part (danbooru-builder--swap layout block other))
          (if (danbooru-builder-text-p part)
              (progn
                (setf (danbooru-builder-text-position part) position)
                (push part texts))
            (cl-incf position)))
        (setf (danbooru-builder-state-texts state)
              (append (seq-filter #'danbooru-builder-text-category
                                  (danbooru-builder-state-texts state))
                      (nreverse texts)))))))

(defun danbooru-builder--add-items (items)
  "Add ITEMS to the section at point, after the entry at point when it fits."
  (let* ((state (danbooru-builder--st))
         (owner (danbooru-builder--owner-at-point))
         (after (danbooru-builder--prop 'danbooru-builder-entry))
         last)
    (dolist (item items)
      (when-let* ((entry (danbooru-builder--add state owner item after)))
        (setq after entry last entry)))
    (danbooru-builder--render)
    (when last (danbooru-builder--goto-prop 'danbooru-builder-entry last))))

(defun danbooru-builder-add ()
  "Add tags to the scene or person at point, chosen with completion.
Catalog tags, the Danbooru vocabulary and free text (a custom tag)."
  (interactive)
  (let ((state (danbooru-builder--st)))
    (danbooru-builder--add-items
     (danbooru-builder--read-items
      (format "Add to %s: " (danbooru-builder--owner-label
                             state (danbooru-builder--owner-at-point)))))))

(defun danbooru-builder-pick-groups ()
  "Pick structured catalog items for the scene or person at point."
  (interactive)
  (require 'danbooru-groups)
  (let ((destination (copy-marker (point) t)))
    (danbooru-groups-pick
     nil (lambda (items)
           (unless (marker-buffer destination) (user-error "Builder buffer no longer exists"))
           (with-current-buffer (marker-buffer destination)
             (goto-char destination)
             (danbooru-builder--add-items (mapcar #'danbooru-builder--catalog-item items)))))))

(defun danbooru-builder-add-in-category (category)
  "Add tags of CATEGORY (default: the category at point) to the section at point."
  (interactive (list (danbooru-builder--read-category
                      (danbooru-builder--prop 'danbooru-builder-category))))
  (danbooru-builder--add-items
   (danbooru-builder--read-items (format "Add %s: " category) category)))

(defun danbooru-builder-remove ()
  "Remove marked tags, or the text, alternative, tag or person at point."
  (interactive)
  (let ((state (danbooru-builder--st))
        (alt (danbooru-builder--prop 'danbooru-builder-alt))
        (entry (danbooru-builder--prop 'danbooru-builder-entry))
        (section (danbooru-builder--prop 'danbooru-builder-section)))
    (cond
     ((danbooru-builder--prop 'danbooru-builder-text)
      (setf (danbooru-builder-state-texts state)
            (delq (danbooru-builder--prop 'danbooru-builder-text)
                  (danbooru-builder-state-texts state))))
     (danbooru-builder--marked
      (dolist (e danbooru-builder--marked)
        (danbooru-builder--remove state e))
      (setq danbooru-builder--marked nil))
     (alt
      (let ((alts (delq alt (danbooru-builder-entry-alts entry))))
        (if alts
            (setf (danbooru-builder-entry-alts entry) alts)
          (danbooru-builder--remove state entry))))
     (entry (danbooru-builder--remove state entry))
     ((danbooru-builder-person-p section)
      (when (y-or-n-p (format "Remove %s and their tags? "
                              (danbooru-builder--person-name state section)))
        (danbooru-builder--remove-person state section)))
     (t (user-error "Nothing to remove here")))
    (danbooru-builder--render)))

(defun danbooru-builder-edit ()
  "Edit what is at point.
A tag or alternative: its prompt text.  A variation: add alternatives.
A person heading: the person.  A free-form text block: its literal text."
  (interactive)
  (danbooru-builder--st)
  (let ((alt(danbooru-builder--prop 'danbooru-builder-alt))
        (entry (danbooru-builder--prop 'danbooru-builder-entry))
        (section (danbooru-builder--prop 'danbooru-builder-section)))
    (cond
     ((danbooru-builder--prop 'danbooru-builder-text)
      (let* ((block (danbooru-builder--prop 'danbooru-builder-text))
             (text (read-string "Free-form text: " (danbooru-builder-text-text block))))
        (when (string-blank-p text) (user-error "Text is empty"))
        (setf (danbooru-builder-text-text block) text)))
     ((and entry (danbooru-builder-entry-vary entry) (not alt))
      (danbooru-builder--add-alternatives entry))
     ((or alt entry)
      (let* ((alt (or alt (car (danbooru-builder-entry-alts entry))))
             (text (string-trim (read-string "Tag text: " (danbooru-builder-alt-tag alt)))))
        (unless (string-empty-p text)
          (setf (danbooru-builder-alt-label alt) text
                (danbooru-builder-alt-tag alt) text))))
     ((danbooru-builder-person-p section) (danbooru-builder-edit-person))
     (t (user-error "Nothing to edit here")))
    (danbooru-builder--render)))

(defun danbooru-builder--add-alternatives (entry)
  "Read more alternatives for variation ENTRY.
Any tag can be an alternative; the variation stays in its category."
  (let* ((cat (danbooru-builder-entry-category entry))
         (have (mapcar #'danbooru-builder-alt-tag (danbooru-builder-entry-alts entry)))
         (items (danbooru-builder--read-items (format "Alternatives (%s): " cat))))
    (dolist (item items)
      (unless (member (danbooru-builder-item-tag item) have)
        (push (danbooru-builder-item-tag item) have)
        (setf (danbooru-builder-entry-alts entry)
              (append (danbooru-builder-entry-alts entry)
                      (list (danbooru-builder--make-alt
                             (danbooru-builder-item-label item)
                             (danbooru-builder-item-tag item)))))))))

(defun danbooru-builder-link (link)
  "Link the variation at point with others named LINK; empty unlinks.
Linked variations step together: the first alternatives in one image,
the second ones in the next, and so on, instead of every combination."
  (interactive
   (let ((entry (danbooru-builder--prop 'danbooru-builder-entry)))
     (unless (and entry (danbooru-builder-entry-vary entry))
       (user-error "Not on a variation"))
     (list (completing-read
            (format-prompt "Link with (empty: unlink)" nil)
            (delete-dups (delq nil (mapcar #'danbooru-builder-entry-link
                                           (danbooru-builder-state-entries
                                            (danbooru-builder--st)))))
            nil nil nil nil (danbooru-builder-entry-link entry)))))
  (let ((entry (danbooru-builder--prop 'danbooru-builder-entry))
        (link (string-trim link)))
    (setf (danbooru-builder-entry-link entry) (unless (string-empty-p link) link))
    (danbooru-builder--render)))

(defun danbooru-builder-vary ()
  "Make or split a variation.
With marked tags of one category: merge them into one variation.  On a
tag: turn it into a variation and read more alternatives.  On a
variation: split its active alternatives back into tags."
  (interactive)
  (let* ((state (danbooru-builder--st))
         (entry (danbooru-builder--prop 'danbooru-builder-entry))
         (marked (seq-filter (lambda (e) (memq e danbooru-builder--marked))
                             (danbooru-builder-state-entries state))))
    (cond
     (marked
      (let ((first (car marked)))
        (unless (seq-every-p (lambda (e)
                               (and (eql (danbooru-builder-entry-owner e)
                                         (danbooru-builder-entry-owner first))
                                    (equal (danbooru-builder-entry-category e)
                                           (danbooru-builder-entry-category first))))
                             marked)
          (user-error "Marked tags must be of one person and category"))
        (setf (danbooru-builder-entry-alts first)
              (apply #'append (mapcar #'danbooru-builder-entry-alts marked))
              (danbooru-builder-entry-vary first) t)
        (dolist (e (cdr marked))
          (danbooru-builder--remove state e))
        (setq danbooru-builder--marked nil)))
     ((null entry) (user-error "No tag here"))
     ((danbooru-builder-entry-vary entry)
      (let ((after entry) first)
        (dolist (alt (danbooru-builder--active-alts entry))
          (let ((e (danbooru-builder--make-entry (danbooru-builder-entry-owner entry)
                                                 (danbooru-builder-entry-category entry)
                                                 (list alt))))
            (danbooru-builder--insert-entry state e after)
            (setq after e first (or first e))))
        (danbooru-builder--remove state entry)
        (danbooru-builder--render)
        (danbooru-builder--goto-prop 'danbooru-builder-entry first)))
     (t
      (setf (danbooru-builder-entry-vary entry) t)
      (unwind-protect
          (danbooru-builder--add-alternatives entry)
        (danbooru-builder--render))))
    (danbooru-builder--render)))

(defun danbooru-builder-toggle-alternative ()
  "Switch the alternative at point off or on."
  (interactive)
  (let ((alt (or (danbooru-builder--prop 'danbooru-builder-alt)
                 (user-error "Not on an alternative of a variation"))))
    (setf (danbooru-builder-alt-off alt) (not (danbooru-builder-alt-off alt)))
    (danbooru-builder--render)))

(defun danbooru-builder--swap (list a b)
  "LIST with elements A and B swapped."
  (mapcar (lambda (x) (cond ((eq x a) b) ((eq x b) a) (t x))) list))

(defun danbooru-builder--move (dir)
  "Move the text, alternative or tag at point one step; DIR is -1 or 1."
  (let* ((state (danbooru-builder--st))
         (text (danbooru-builder--prop 'danbooru-builder-text))
         (alt (danbooru-builder--prop 'danbooru-builder-alt))
         (entry (danbooru-builder--prop 'danbooru-builder-entry)))
    (cond
     (text (danbooru-builder--move-text state text dir))
     ((null entry) (user-error "No tag or free-form text here"))
     (alt
      (let* ((alts (danbooru-builder-entry-alts entry))
             (other (nth (+ (cl-position alt alts) dir) alts)))
        (when (and other (>= (+ (cl-position alt alts) dir) 0))
          (setf (danbooru-builder-entry-alts entry)
                (danbooru-builder--swap alts alt other)))))
     (t
      (let* ((siblings (danbooru-builder--entries state (danbooru-builder-entry-owner entry)
                                                  (danbooru-builder-entry-category entry)))
             (i (+ (cl-position entry siblings) dir))
             (other (and (>= i 0) (nth i siblings))))
        (when other
          (setf (danbooru-builder-state-entries state)
                (danbooru-builder--swap (danbooru-builder-state-entries state)
                                        entry other))))))
    (danbooru-builder--render)))

(defun danbooru-builder-move-up ()
  "Move the tag, alternative or free-form text at point up."
  (interactive)
  (danbooru-builder--move -1))

(defun danbooru-builder-move-down ()
  "Move the tag, alternative or free-form text at point down."
  (interactive)
  (danbooru-builder--move 1))

(defun danbooru-builder-mark (&optional unmark)
  "Mark the tag at point and move to the next line; UNMARK unmarks."
  (interactive)
  (when-let* ((entry (danbooru-builder--prop 'danbooru-builder-entry)))
    (setq danbooru-builder--marked (delq entry danbooru-builder--marked))
    (unless unmark (push entry danbooru-builder--marked))
    (danbooru-builder--render))
  (forward-line 1))

(defun danbooru-builder-unmark ()
  "Unmark the tag at point and move to the next line."
  (interactive)
  (danbooru-builder-mark t))

(defun danbooru-builder-unmark-all ()
  "Unmark all tags."
  (interactive)
  (setq danbooru-builder--marked nil)
  (danbooru-builder--render))

(defun danbooru-builder--read-person (&optional person)
  "Read (TYPE POSITION NAME), defaults from PERSON."
  (let* ((type (completing-read "Type: " (mapcar #'car danbooru-builder--person-types)
                                nil t nil nil
                                (if person (danbooru-builder-person-type person) "girl")))
         (pos-name (completing-read
                    "Position: " (mapcar #'car danbooru-builder--positions) nil t nil nil
                    (or (car (rassoc (and person (danbooru-builder-person-position person))
                                     danbooru-builder--positions))
                        "no position")))
         (name (string-trim (read-string "Name (empty: none): "
                                         (and person (danbooru-builder-person-name person))))))
    (list type (cdr (assoc pos-name danbooru-builder--positions)) name)))

(defun danbooru-builder-add-person ()
  "Add a person and move to their section."
  (interactive)
  (let* ((state (danbooru-builder--st))
         (person (apply #'danbooru-builder--add-person state
                        (danbooru-builder--read-person))))
    (danbooru-builder--render)
    (danbooru-builder--goto-prop 'danbooru-builder-section person)))

(defun danbooru-builder-edit-person ()
  "Edit the type, position and name of the person at point."
  (interactive)
  (let ((person (danbooru-builder--prop 'danbooru-builder-section)))
    (unless (danbooru-builder-person-p person)
      (user-error "Not in a person's section"))
    (pcase-let ((`(,type ,pos ,name) (danbooru-builder--read-person person)))
      (setf (danbooru-builder-person-type person) type
            (danbooru-builder-person-position person) pos
            (danbooru-builder-person-name person) name))
    (danbooru-builder--render)))

(defun danbooru-builder-copy-prompt ()
  "Copy the prompt (the first variant) to the kill ring."
  (interactive)
  (let ((prompt (danbooru-builder--build-prompt (danbooru-builder--st))))
    (kill-new prompt)
    (message "Copied: %s" prompt)))

(defun danbooru-builder-reload ()
  "Reload the config, tag files and vocabulary."
  (interactive)
  (let ((state (danbooru-builder--st)))
    (danbooru-catalog-get t)
    (setq danbooru-builder--catalog nil)
    (setf (danbooru-builder-state-catalog state) (danbooru-builder--catalog))
    (danbooru-builder--render)
    (message "Loaded %d categories, %d completion candidates"
             (length (danbooru-builder-catalog-categories danbooru-builder--catalog))
             (length (danbooru-builder-catalog-candidates danbooru-builder--catalog)))))

(defun danbooru-builder-next-section (&optional n)
  "Move to the next scene or person heading; N times."
  (interactive "p")
  (dotimes (_ (abs (or n 1)))
    (let ((section (danbooru-builder--prop 'danbooru-builder-section)))
      (if (>= (or n 1) 0)
          (progn
            (forward-line 1)
            (while (and (not (eobp))
                        (or (eq (danbooru-builder--prop 'danbooru-builder-section) section)
                            (null (danbooru-builder--prop 'danbooru-builder-section))))
              (forward-line 1)))
        (forward-line -1)
        (while (and (not (bobp))
                    (or (null (danbooru-builder--prop 'danbooru-builder-section))
                        (eq (danbooru-builder--prop 'danbooru-builder-section)
                            (save-excursion (forward-line -1)
                                            (danbooru-builder--prop 'danbooru-builder-section)))))
          (forward-line -1))))))

(defun danbooru-builder-previous-section (&optional n)
  "Move to the previous scene or person heading; N times."
  (interactive "p")
  (danbooru-builder-next-section (- (or n 1))))

;;; ── Generation ──

(defvaralias 'danbooru-builder--max-batch 'danbooru-language-max-batch)

(defconst danbooru-builder--confirm-batch 20
  "Generate asks before making more images than this.")

(defun danbooru-builder--path (path)
  "PATH with ~ and $VARS expanded, relative to `danbooru-builder-directory'."
  (expand-file-name (substitute-in-file-name path) danbooru-builder-directory))

(defun danbooru-builder--output-dir (state)
  "Directory the images of STATE go to."
  (danbooru-builder--path
   (or danbooru-builder-output-dir
       (danbooru-builder--cfg (danbooru-builder-state-catalog state) 'output_dir "outputs"))))

(defun danbooru-builder--profile (state)
  "Config alist of the current profile of STATE."
  (when-let* ((name (plist-get (danbooru-builder-state-gen state) :profile)))
    (alist-get (intern name) (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                                                    'profiles))))

(defun danbooru-builder--plan (state)
  "The images of one generate: ((SEED . PICK) ...), seeds outermost.
SEED is nil for a random seed; all variants of one seed come out together."
  (when (> (danbooru-builder--batch-size state) danbooru-language-max-batch)
    (user-error "Builder batch exceeds limit %d" danbooru-language-max-batch))
  (let* ((gen (danbooru-builder-state-gen state))
         (seeds (if (< (plist-get gen :seed) 0)
                    (list nil)
                  (danbooru-builder--seeds state)))
         (variants (danbooru-builder--variants state)))
    (cl-loop for seed in seeds
             nconc (mapcar (lambda (pick) (cons seed pick)) variants))))

(defun danbooru-builder--full-prompt (state pick)
  "Prompt of variant PICK with the profile's prompt_prefix in front."
  (let ((prefix (string-trim (or (alist-get 'prompt_prefix (danbooru-builder--profile state)) "")
                             "[ ,]+" "[ ,]+")))
    (string-join (seq-remove #'string-empty-p
                             (list prefix (danbooru-builder--build-prompt state pick)))
                 ", ")))

(defun danbooru-builder--pick-label (pick)
  "The chosen alternatives of variant PICK, or nil without variations."
  (when pick
    (mapconcat (lambda (cell) (danbooru-builder-alt-label (cdr cell))) pick " / ")))

(defun danbooru-builder--preview-file (state)
  "The live preview image of sd-cli, nil when config.json turns it off."
  (let ((mode (danbooru-builder--cfg (danbooru-builder-state-catalog state) 'preview "none")))
    (unless (member mode '(nil "" "none"))
      (expand-file-name ".preview.png" (danbooru-builder--output-dir state)))))

(defun danbooru-builder--command (state prompt seed out)
  "sd-cli argument list making OUT from PROMPT and SEED with STATE's settings."
  (let* ((gen (danbooru-builder-state-gen state))
         (sd (danbooru-builder--path
              (danbooru-builder--cfg (danbooru-builder-state-catalog state) 'sd_cli "sd-cli"))))
    (unless (file-executable-p sd)
      (user-error "sd-cli not found: %s (sd_cli in config.json)" sd))
    (append (list sd)
            (mapcar (lambda (arg) (if (string-prefix-p "~" arg) (expand-file-name arg) arg))
                    (alist-get 'args (danbooru-builder--profile state)))
            (list "-p" prompt
                  "-n" (or (danbooru-builder-state-negative state) "")
                  "--cfg-scale" (format "%s" (plist-get gen :cfg))
                  "--sampling-method" (plist-get gen :sampler)
                  "--scheduler" (plist-get gen :scheduler)
                  "-W" (number-to-string (plist-get gen :width))
                  "-H" (number-to-string (plist-get gen :height))
                  "--steps" (number-to-string (plist-get gen :steps))
                  "-s" (number-to-string seed)
                  "-o" out)
            (when-let* ((preview (danbooru-builder--preview-file state)))
              (list "--preview" (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                                                       'preview)
                    "--preview-path" preview
                    "--preview-interval"
                    (format "%s" (danbooru-builder--cfg (danbooru-builder-state-catalog state)
                                                        'preview_interval 1)))))))

(defvar-local danbooru-builder--prepared nil)
(defvar-local danbooru-builder--prepared-key nil)

(defun danbooru-builder--runtime-prepared (state)
  "Project legacy STATE through the shared compiler and prepare it once."
  (require 'danbooru-builder-source)
  (let ((key (danbooru-builder--serialize state)))
    (unless (and danbooru-builder--prepared (equal key danbooru-builder--prepared-key))
      (let* ((text (danbooru-builder-source-convert (read key) (danbooru-builder-state-catalog state) t))
             (compilation (danbooru-language-compile text))
             (context (plist-put (danbooru-runtime-context) :parameter-keys
                                 '(:profile :width :height :steps :cfg :sampler :scheduler :neg)))
             (prepared (danbooru-runtime-prepare (danbooru-runtime-plan compilation nil (current-buffer)) context)))
        (dolist (job (danbooru-prepared-jobs prepared))
          (let ((data (read key)) used)
            (setf (plist-get (plist-get data :gen) :seed) (plist-get job :seed)
                  (plist-get (plist-get data :gen) :seed-end) -1)
            (dolist (entry (plist-get data :entries))
              (when (plist-get entry :vary)
                (let* ((marker (danbooru-builder--marker (plist-get entry :category) used))
                       (chosen (cdr (assoc marker (plist-get job :choices)))))
                  (push marker used)
                  (when chosen
                    (setf (plist-get entry :alts)
                          (mapcar (lambda (alt)
                                    (plist-put alt :off (not (and (equal (plist-get alt :label) (nth 1 chosen))
                                                                  (equal (plist-get alt :tag) (nth 2 chosen))))))
                                  (plist-get entry :alts)))))))
            (nconc job (list :meta (list :builder (prin1-to-string data))))))
        (setq danbooru-builder--prepared prepared danbooru-builder--prepared-key key)))
    danbooru-builder--prepared))

(defun danbooru-builder--jobs (state)
  "Compatibility concrete jobs from the shared compiler/preparation path."
  (danbooru-prepared-jobs (danbooru-builder--runtime-prepared state)))

(defun danbooru-builder--serialize-for-image (state seed pick)
  "STATE serialized to remake one image: SEED as its only seed and in
every variation only the alternative of variant PICK switched on."
  (let ((gen (danbooru-builder-state-gen state))
        (offs (cl-loop for (entry . _) in pick
                       append (mapcar (lambda (alt) (cons alt (danbooru-builder-alt-off alt)))
                                      (danbooru-builder-entry-alts entry)))))
    (unwind-protect
        (progn
          (setf (danbooru-builder-state-gen state)
                (plist-put (plist-put (copy-sequence gen) :seed seed) :seed-end -1))
          (pcase-dolist (`(,entry . ,chosen) pick)
            (dolist (alt (danbooru-builder-entry-alts entry))
              (setf (danbooru-builder-alt-off alt) (not (eq alt chosen)))))
          (danbooru-builder--serialize state))
      (setf (danbooru-builder-state-gen state) gen)
      (pcase-dolist (`(,alt . ,off) offs)
        (setf (danbooru-builder-alt-off alt) off)))))

(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))

(defun danbooru-builder--image-at-point ()
  "The image of the current image buffer or the dired line, if any."
  (let ((file (cond ((derived-mode-p 'dired-mode) (dired-get-filename nil t))
                    (t buffer-file-name))))
    (and file (string-match-p "\\.png\\'" file) file)))

;;;###autoload
(defun danbooru-builder-open-image (image)
  "Load the builder setup that made IMAGE, with its seed.
IMAGE defaults to the image shown or the one on the dired line."
  (interactive
   (list (or (danbooru-builder--image-at-point)
             (read-file-name "Image: " nil nil t nil
                             (lambda (f) (or (file-directory-p f)
                                             (string-suffix-p ".png" f)))))))
  (let* ((meta-file (concat image ".json"))
         (setup (and (file-readable-p meta-file)
                     (gethash "builder" (danbooru-builder--json-file meta-file)))))
    (unless (stringp setup)
      (user-error "%s has no builder setup (not made by danbooru-builder?)"
                  (file-name-nondirectory image)))
    (let ((buf (danbooru-builder--get-buffer)))
      (with-current-buffer buf
        (danbooru-builder--confirm-discard)
        (danbooru-builder--install
         (danbooru-builder--state-from-data
          (condition-case err
              (car (read-from-string setup))
            (error (user-error "Cannot read the builder setup of %s: %s"
                               (file-name-nondirectory image) (error-message-string err))))
          (danbooru-builder--catalog))
         nil))
      (pop-to-buffer-same-window buf)
      (message "Loaded the setup of %s (unsaved)" (file-name-nondirectory image)))))

(defun danbooru-builder--image-matches-alternative-p (image entry alt)
  "Return non-nil when IMAGE's saved setup used ENTRY's ALT."
  (condition-case nil
      (let* ((metadata (danbooru-builder--json-file (concat image ".json")))
             (setup (gethash "builder" metadata))
             (read-eval nil)
             (data (and (stringp setup) (car (read-from-string setup)))))
        (seq-some
         (lambda (saved)
           (and (equal (plist-get saved :owner) (danbooru-builder-entry-owner entry))
                (equal (plist-get saved :category) (danbooru-builder-entry-category entry))
                (plist-get saved :vary)
                (seq-some (lambda (candidate)
                            (and (not (plist-get candidate :off))
                                 (equal (plist-get candidate :label)
                                        (danbooru-builder-alt-label alt))
                                 (equal (plist-get candidate :tag)
                                        (danbooru-builder-alt-tag alt))))
                          (plist-get saved :alts))))
         (plist-get data :entries)))
    (error nil)))

(defun danbooru-builder-show-alternative-image ()
  "Show the latest image generated using the variation alternative at point.
Other variations do not restrict the match.  Search the configured output
directory and use the existing image sidecar metadata."
  (interactive)
  (let* ((state (danbooru-builder--st))
         (alt (or (danbooru-builder--prop 'danbooru-builder-alt)
                  (user-error "Not on an alternative of a variation")))
         (entry (danbooru-builder--prop 'danbooru-builder-entry))
         (dir (danbooru-builder--output-dir state))
         (images (when (file-directory-p dir)
                   (directory-files dir t "\\.png\\'")))
         (images (sort images (lambda (a b)
                                (time-less-p (file-attribute-modification-time (file-attributes b))
                                             (file-attribute-modification-time (file-attributes a))))))
         (image (seq-find (lambda (file)
                            (danbooru-builder--image-matches-alternative-p file entry alt))
                          images)))
    (unless image
      (user-error "No generated image found for %s" (danbooru-builder-alt-label alt)))
    (let ((window (display-buffer (find-file-noselect image)
                                  '((display-buffer-in-side-window)
                                    (side . right) (slot . 0)))))
      (unless window (user-error "Could not display %s" image))
      (message "Showing %s" (file-name-nondirectory image)))))

(defun danbooru-builder-generate ()
  "Submit the legacy view through the same frozen compiler/runtime boundary."
  (interactive)
  (let ((prepared (danbooru-builder--runtime-prepared (danbooru-builder--st))))
    (when (and (> (length (danbooru-prepared-jobs prepared)) danbooru-builder--confirm-batch)
               (not (y-or-n-p (format "Generate %d images? " (length (danbooru-prepared-jobs prepared))))))
      (user-error "Cancelled"))
    (prog1 (danbooru-runtime-submit prepared)
      (setq danbooru-builder--prepared nil danbooru-builder--prepared-key nil))))

(defun danbooru-builder-cancel ()
  "Stop the running generation and drop the queued images."
  (interactive)
  (danbooru-cancel))

(defun danbooru-builder-show-variants ()
  "Prepare and show exactly the requests legacy Generate will submit."
  (interactive)
  (danbooru-runtime-preview (danbooru-builder--runtime-prepared (danbooru-builder--st)) "*danbooru-variants*"))

;;; ── Files ──

(defun danbooru-builder--save-directory ()
  "Default directory for builder files."
  (file-name-as-directory
   (expand-file-name (or danbooru-builder-save-directory
                         (expand-file-name "presets" danbooru-builder-directory)))))

(defun danbooru-builder--serialize (state)
  "STATE as the text of a builder file: Lisp data, one tag slot per line."
  (let ((print-escape-newlines t)
        (print-length nil)
        (print-level nil))
    (cl-flet ((alt (a) (append (list :label (danbooru-builder-alt-label a)
                                     :tag (danbooru-builder-alt-tag a))
                               (and (danbooru-builder-alt-off a) (list :off t))))
              (lines (items) (mapconcat (lambda (x) (format "%S" x)) items "\n  ")))
      (concat
       ";;; danbooru-builder  -*- coding: utf-8 -*-\n"
       ";; Load with o in M-x danbooru-builder, or C-c C-c in this file.\n\n"
       (format "(:version 1\n :style %s\n :extra %S\n :negative %S\n :gen %S\n"
               (danbooru-builder-state-style state)
               (or (danbooru-builder-state-extra state) "")
               (or (danbooru-builder-state-negative state) "")
               (danbooru-builder-state-gen state))
       " :texts\n ("
       (lines (mapcar (lambda (block)
                       (append (list :text (danbooru-builder-text-text block))
                               (if (danbooru-builder-text-category block)
                                   (list :category (danbooru-builder-text-category block)
                                         :owner (danbooru-builder-text-owner block))
                                 (list :position (danbooru-builder-text-position block)))))
                     (danbooru-builder-state-texts state)))
       ")\n"
       " :persons\n ("
       (lines (mapcar (lambda (p)
                        (list :id (danbooru-builder-person-id p)
                              :type (danbooru-builder-person-type p)
                              :position (danbooru-builder-person-position p)
                              :name (danbooru-builder-person-name p)))
                      (danbooru-builder-state-persons state)))
       ")\n :entries\n ("
       (lines (mapcar (lambda (e)
                        (append (list :owner (danbooru-builder-entry-owner e)
                                      :category (danbooru-builder-entry-category e))
                                (and (danbooru-builder-entry-vary e) (list :vary t))
                                (and (danbooru-builder-entry-link e)
                                     (list :link (danbooru-builder-entry-link e)))
                                (list :alts (mapcar #'alt (danbooru-builder-entry-alts e)))))
                      (danbooru-builder-state-entries state)))
       "))\n"))))

(defun danbooru-builder--modified-p ()
  "Non-nil when the builder changed since it was last saved or loaded."
  (and danbooru-builder--state
       (not (equal (danbooru-builder--serialize danbooru-builder--state)
                   danbooru-builder--saved))))

(defun danbooru-builder--state-from-data (data catalog)
  "A state over CATALOG from DATA read from a builder file.
Unknown persons' tags go to the scene; settings that are missing or of
the wrong type keep the profile defaults."
  (cl-flet ((bad (what) (user-error "Not a valid builder file: %s" what)))
    (unless (and (plistp data) (plist-member data :version))
      (bad "no (:version ...) form"))
    (unless (eql (plist-get data :version) 1)
      (bad (format "unknown version %S" (plist-get data :version))))
    (let* ((state (danbooru-builder--new-state catalog))
           (saved (plist-get data :gen))
           (profile (plist-get saved :profile))
           persons ids)
      ;; settings: the saved profile's defaults, then the saved values
      (if (member profile (danbooru-builder--profiles state))
          (danbooru-builder--apply-profile state profile)
        (when profile
          (message "Profile %s is not in config.json, using %s" profile
                   (plist-get (danbooru-builder-state-gen state) :profile))))
      (pcase-dolist (`(,key ,ok) '((:width natnump) (:height natnump) (:steps natnump)
                                   (:cfg numberp) (:sampler stringp) (:scheduler stringp)
                                   (:seed integerp) (:seed-end integerp)
                                   (:seed-step natnump) (:backend stringp)))
        (let ((value (plist-get saved key)))
          (when (funcall ok value)
            (setf (danbooru-builder-state-gen state)
                  (plist-put (danbooru-builder-state-gen state) key value)))))
      (setf (danbooru-builder-state-style state)
            (if (eq (plist-get data :style) 'natural) 'natural 'tags))
      (let ((extra (plist-get data :extra)) (neg (plist-get data :negative)))
        (setf (danbooru-builder-state-extra state) (if (stringp extra) extra ""))
        (when (stringp neg) (setf (danbooru-builder-state-negative state) neg)))
      (dolist (p (plist-get data :persons))
        (let ((id (and (plistp p) (plist-get p :id)))
              (type (plist-get p :type))
              (pos (plist-get p :position))
              (name (plist-get p :name)))
          (unless (and (natnump id) (not (memq id ids)))
            (bad (format "person %S" p)))
          (push id ids)
          (push (danbooru-builder--make-person
                 id (if (assoc type danbooru-builder--person-types) type "girl")
                 (if (stringp pos) pos "") (and (stringp name) name))
                persons)))
      (setf (danbooru-builder-state-persons state) (nreverse persons))
      (setf (danbooru-builder-state-texts state)
            (mapcar
             (lambda (block)
               (let ((text (and (plistp block) (plist-get block :text)))
                     (category (plist-get block :category))
                     (owner (plist-get block :owner))
                     (position (plist-get block :position)))
                 (unless (and (stringp text) (not (string-blank-p text))
                              (if category
                                  (and (stringp category) (not (string-blank-p category)))
                                (natnump position)))
                   (bad (format "free-form text %S" block)))
                 (danbooru-builder--make-text
                  text (unless category position) category
                  (and category (memq owner ids)
                       (not (danbooru-builder--scene-category-p state category)) owner))))
             (plist-get data :texts)))
      (setf (danbooru-builder-state-entries state)
            (mapcar
             (lambda (e)
               (let ((cat (and (plistp e) (plist-get e :category)))
                     (owner (plist-get e :owner))
                     (alts (plist-get e :alts)))
                 (unless (and (stringp cat) (consp alts))
                   (bad (format "tag slot %S" e)))
                 (let ((alts (mapcar
                              (lambda (a)
                                (let ((tag (and (plistp a) (plist-get a :tag)))
                                      (label (plist-get a :label)))
                                  (unless (stringp tag) (bad (format "tag %S" a)))
                                  (let ((alt (danbooru-builder--make-alt
                                              (if (stringp label) label tag) tag)))
                                    (setf (danbooru-builder-alt-off alt) (and (plist-get a :off) t))
                                    alt)))
                              alts)))
                   (let ((entry (danbooru-builder--make-entry
                                 (and (memq owner ids)
                                      (not (danbooru-builder--scene-category-p state cat))
                                      owner)
                                 cat alts
                                 (or (and (plist-get e :vary) t) (cdr alts) nil)))
                         (link (plist-get e :link)))
                     (when (and (stringp link) (danbooru-builder-entry-vary entry))
                       (setf (danbooru-builder-entry-link entry) link))
                     entry))))
             (plist-get data :entries)))
      state)))

(defun danbooru-builder--read-file (file)
  "The Lisp data in builder FILE."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (goto-char (point-min))
    (condition-case err
        (read (current-buffer))
      (end-of-file (user-error "Cannot read %s: it ends too early (unbalanced parentheses?)"
                               (abbreviate-file-name file)))
      (error (user-error "Cannot read %s: %s" (abbreviate-file-name file)
                         (error-message-string err))))))

(defun danbooru-builder--confirm-discard ()
  "Ask before throwing away unsaved builder changes."
  (when (and (buffer-modified-p)
             (not (y-or-n-p "Discard the unsaved builder changes? ")))
    (user-error "Cancelled")))

(defun danbooru-builder--install (state file)
  "Make STATE the builder's state, loaded from or new as FILE (nil: new)."
  (setq danbooru-builder--state state
        danbooru-builder--file (and file (expand-file-name file))
        danbooru-builder--marked nil
        danbooru-builder--saved (danbooru-builder--serialize state))
  (danbooru-builder--render)
  (goto-char (point-min)))

(defun danbooru-builder--read-save-file ()
  "Read the file name to save to; .dbb is added when there is no extension."
  (let ((file (expand-file-name
               (read-file-name "Save builder to: "
                               (if danbooru-builder--file
                                   (file-name-directory danbooru-builder--file)
                                 (danbooru-builder--save-directory))
                               nil nil
                               (and danbooru-builder--file
                                    (file-name-nondirectory danbooru-builder--file))))))
    (when (directory-name-p file)
      (user-error "Need a file name"))
    (unless (file-name-extension file)
      (setq file (concat file ".dbb")))
    (when (and (file-exists-p file)
               (not (equal file danbooru-builder--file))
               (not (y-or-n-p (format "%s exists; overwrite? " (abbreviate-file-name file)))))
      (user-error "Not saved"))
    file))

(defun danbooru-builder-save (&optional file)
  "Save the builder to its file, asking for one the first time.
FILE saves there instead and makes it the builder's file."
  (interactive)
  (let* ((state (danbooru-builder--st))
         (file (or file danbooru-builder--file (danbooru-builder--read-save-file)))
         (text (danbooru-builder--serialize state)))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region text nil file nil 'silent))
    (setq danbooru-builder--file file
          danbooru-builder--saved text)
    (danbooru-builder--render)
    (message "Saved %s" (abbreviate-file-name file))))

(defun danbooru-builder-save-as ()
  "Save the builder to a new file."
  (interactive)
  (danbooru-builder--st)
  (danbooru-builder-save (danbooru-builder--read-save-file)))

;;;###autoload
(defun danbooru-builder-open-legacy (file)
  "Load builder FILE (.dbb) into the builder."
  (interactive
   (list (read-file-name "Open builder file: " (danbooru-builder--save-directory) nil t nil
                         (lambda (f) (or (file-directory-p f)
                                         (string-suffix-p ".dbb" f))))))
  (let ((buf (danbooru-builder--get-buffer)))
    (with-current-buffer buf
      (danbooru-builder--confirm-discard)
      (danbooru-builder--install
       (danbooru-builder--state-from-data (danbooru-builder--read-file file)
                                          (danbooru-builder--catalog))
       file))
    (pop-to-buffer-same-window buf)
    (message "Loaded %s" (abbreviate-file-name file))))

(defun danbooru-builder-new ()
  "Start over with an empty, unsaved builder."
  (interactive)
  (danbooru-builder--st)
  (danbooru-builder--confirm-discard)
  (danbooru-builder--install (danbooru-builder--new-state (danbooru-builder--catalog)) nil))

(defun danbooru-builder--kill-buffer-query ()
  "Ask before killing a builder with unsaved changes."
  (or (not (buffer-modified-p))
      (y-or-n-p "The builder has unsaved changes; kill it anyway? ")))

(defun danbooru-builder--kill-emacs-query ()
  "Ask before exiting Emacs with unsaved builder changes."
  (let ((buf (get-buffer "*danbooru-builder*")))
    (or (not (and buf (buffer-modified-p buf)))
        (y-or-n-p "The danbooru builder has unsaved changes; exit anyway? "))))

(add-hook 'kill-emacs-query-functions #'danbooru-builder--kill-emacs-query)

(defvar-keymap danbooru-builder-file-mode-map
  :doc "Keymap of `danbooru-builder-file-mode'."
  "C-c C-c" #'danbooru-builder-open-this-file)

;;;###autoload
(define-derived-mode danbooru-builder-file-mode lisp-data-mode "Danbooru-Builder-File"
  "A saved danbooru builder (.dbb).  \\[danbooru-builder-open-this-file] loads it.

\\{danbooru-builder-file-mode-map}")

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.dbb\\'" . danbooru-builder-file-mode))

(defun danbooru-builder-open-this-file ()
  "Import the visited builder data without changing its .dbb file."
  (interactive)
  (unless buffer-file-name (user-error "Buffer is not visiting a file"))
  (danbooru-builder-open buffer-file-name))

;;; ── Export to .danbooru ──

(defun danbooru-builder--marker (category used)
  "A $MARKER for a variation of CATEGORY that is not in USED."
  (let* ((base (concat "$" (upcase (string-trim (replace-regexp-in-string
                                                 "[^[:alnum:]]+" "_" category)
                                                "_+" "_+"))))
         (name base)
         (i 1))
    (while (member name used)
      (setq name (format "%s%d" base (cl-incf i))))
    name))

(defun danbooru-builder--alt-prompt-text (state entry alt)
  "The prompt text ALT of variation ENTRY puts where its marker stands."
  (let* ((cat (danbooru-builder-entry-category entry))
         (names (and (eq (danbooru-builder-state-style state) 'natural)
                     (danbooru-builder-state-persons state)
                     (= (danbooru-builder--section-of state cat)
                        (danbooru-builder--section-of state "character")))))
    (string-join
     (delete-dups
      (seq-remove #'string-empty-p
                  (mapcar (lambda (piece)
                            (let ((tag (danbooru-builder--format-tag state piece cat)))
                              (if names (danbooru-builder--name-case tag) tag)))
                          (split-string (danbooru-builder-alt-tag alt) ","))))
     ", ")))

(defun danbooru-builder--export-text (state &optional single expanded)
  "STATE as the text of a .danbooru prompt file.
Each variation becomes a $MARKER with a (:vary ...) of its alternatives.
In tags style every part of the prompt is one string, unless SINGLE,
which writes the whole prompt as one string.  EXPANDED uses whole-prompt
alternatives to preserve text positions when variations change tag counts."
  (let* ((print-escape-newlines t)
         (gen (danbooru-builder-state-gen state))
         (axes (unless expanded (danbooru-builder--axes state)))
         (prompts (and expanded
                       (mapcar (lambda (variant)
                                 (danbooru-builder--full-prompt state variant))
                               (danbooru-builder--variants state))))
         (whole-marker "$PROMPT")
         used
         (pick (mapcar (lambda (axis)
                         (let ((marker (danbooru-builder--marker
                                        (danbooru-builder-entry-category (car axis)) used)))
                           (push marker used)
                           (cons (car axis) (danbooru-builder--make-alt marker marker))))
                       axes))
         (markers (mapcar (lambda (cell) (danbooru-builder-alt-tag (cdr cell))) pick))
         (parts (let ((danbooru-builder--raw-alts (mapcar #'cdr pick)))
                  (danbooru-builder--prompt-parts state pick)))
         (prefix (string-trim (or (alist-get 'prompt_prefix (danbooru-builder--profile state)) "")
                              "[ ,]+" "[ ,]+"))
         (strings (append (unless (string-empty-p prefix) (list prefix))
                          (if (or single (not (equal (car parts) ", ")))
                              (list (string-join (cdr parts) (car parts)))
                            (cdr parts))))
         (seed (plist-get gen :seed))
         (end (plist-get gen :seed-end))
         (negative (or (danbooru-builder-state-negative state) "")))
    (when expanded
      (while (seq-some (lambda (prompt) (string-search whole-marker prompt)) prompts)
        (setq whole-marker (concat whole-marker "_")))
      (setq strings (list whole-marker) markers (list whole-marker)))
    (let ((text (concat
                 ";;; Exported from the danbooru builder"
                 (if danbooru-builder--file
                     (format " (%s)" (file-name-nondirectory danbooru-builder--file))
                   "")
                 (format-time-string ", %Y-%m-%d %H:%M.\n")
                 (format ";; Not in this format: profile %s, %s/%s, %s style%s.\n"
                         (plist-get gen :profile) (plist-get gen :sampler) (plist-get gen :scheduler)
                         (danbooru-builder-state-style state)
                         (if (> end seed -1) (format ", seeds %d..%d/%d" seed end (plist-get gen :seed-step)) ""))
                 ";; C-c C-c generates, C-c C-p shows the prompt.\n\n"
                 "("
                 (mapconcat (lambda (s) (if (member s markers) s (format "%S" s))) strings "\n ")
                 ")\n\n"
                 (mapconcat (lambda (cell)
                              (format "(:vary %s %s)\n"
                                      (danbooru-builder-alt-tag (cdr cell))
                                      (mapconcat (lambda (alt)
                                                   (format "%S" (danbooru-builder--alt-prompt-text
                                                                 state (car cell) alt)))
                                                 (cdr (assq (car cell) axes))
                                                 "\n       ")))
                            pick "")
                 (if expanded
                     (format "(:vary %s %s)\n" whole-marker
                             (mapconcat (lambda (prompt) (format "%S" prompt)) prompts "\n       "))
                   "")
                 (if (string-empty-p negative) "" (format "(:neg %S)\n" negative))
                 (format "(:size %d %d)\n(:steps %d)\n(:cfg %s)\n(:seed %d)\n"
                         (plist-get gen :width) (plist-get gen :height)
                         (plist-get gen :steps) (plist-get gen :cfg) seed))))
      ;; Legacy positions can fall inside compound alternatives.
      ;; Whole-prompt alternatives also retain repeated literal text, which
      ;; the prompt compiler would otherwise deduplicate as separate tags.
      (if (and (danbooru-builder-state-texts state) (not expanded)
               (not (danbooru-builder--export-matches-p state text)))
          (danbooru-builder--export-text state single t)
        text))))

(defun danbooru-builder--export-matches-p (state text)
  "Non-nil when danbooru.el makes the builder's prompts from TEXT."
  (equal (condition-case nil
             (mapcar (lambda (job) (plist-get job :prompt)) (danbooru--expand text))
           (error nil))
         (mapcar (lambda (pick) (danbooru-builder--full-prompt state pick))
                 (danbooru-builder--variants state))))

(defun danbooru-builder--read-export-file ()
  "Read the .danbooru file name to export to."
  (let* ((dir (if danbooru-builder--file
                  (file-name-directory danbooru-builder--file)
                (danbooru-builder--save-directory)))
         (name (concat (if danbooru-builder--file
                           (file-name-base danbooru-builder--file)
                         "builder")
                       ".danbooru"))
         (file (expand-file-name (read-file-name "Export to .danbooru file: " dir nil nil name))))
    (when (directory-name-p file)
      (user-error "Need a file name"))
    (unless (file-name-extension file)
      (setq file (concat file ".danbooru")))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "%s exists; overwrite? " (abbreviate-file-name file)))))
      (user-error "Not exported"))
    file))

(defun danbooru-builder-export (file)
  "Write the builder as a .danbooru prompt FILE for `danbooru-prompt-mode'.
Variations become (:vary $MARKER ...).  The file makes the same prompts
as the builder; the profile, sampler, scheduler and seed range are not
part of that format and are noted in a comment."
  (interactive (progn (danbooru-builder--st) (list (danbooru-builder--read-export-file))))
  (let* ((state (danbooru-builder--st))
         (text (danbooru-builder--export-text state)))
    (when (string-empty-p (danbooru-builder--build-prompt state))
      (user-error "The prompt is empty, nothing to export"))
    (cond
     ((and (seq-some (lambda (axis) (danbooru-builder-entry-link (car axis)))
                    (danbooru-builder--axes state))
           (not (danbooru-builder--export-matches-p state text)))
      (display-warning
       'danbooru-builder
       (format "danbooru.el has no linked variations: they are exported as independent \
:vary forms, which make every combination (%d prompts instead of %d)"
               (cl-reduce #'* (mapcar (lambda (a) (length (cdr a))) (danbooru-builder--axes state))
                          :initial-value 1)
               (danbooru-builder--variant-count state))))
     ((not (danbooru-builder--export-matches-p state text))
      (setq text (danbooru-builder--export-text state t))
      (unless (danbooru-builder--export-matches-p state text)
        (display-warning 'danbooru-builder
                         "The exported file may make slightly different prompts"))))
    (make-directory (file-name-directory file) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region text nil file nil 'silent))
    (when-let* ((buf (get-file-buffer file)))
      (with-current-buffer buf (revert-buffer t t)))
    (display-buffer (find-file-noselect file))
    (message "Exported %s" (abbreviate-file-name file))))

;;; ── Settings menu ──

(defconst danbooru-builder--samplers
  '("euler_a" "euler" "heun" "dpm2" "dpm++2s_a" "dpm++2m" "dpm++2mv2" "dpm++2m_sde"
    "ipndm" "ipndm_v" "lcm" "ddim_trailing" "tcd" "res_multistep" "er_sde" "lms")
  "Sampling methods of sd-cli.")

(defconst danbooru-builder--schedulers
  '("karras" "discrete" "exponential" "ays" "gits" "sgm_uniform" "simple"
    "smoothstep" "kl_optimal" "beta")
  "Schedulers of sd-cli.")

(defun danbooru-builder--buffer ()
  "The builder buffer."
  (or (get-buffer "*danbooru-builder*")
      (user-error "No danbooru builder; run M-x danbooru-builder")))

(defun danbooru-builder--settings-state ()
  "State of the builder buffer, from wherever the settings menu runs."
  (buffer-local-value 'danbooru-builder--state (danbooru-builder--buffer)))

(defun danbooru-builder--gen (key)
  "Generation setting KEY of the builder."
  (plist-get (danbooru-builder-state-gen (danbooru-builder--settings-state)) key))

(defun danbooru-builder--set-gen (&rest settings)
  "Set generation SETTINGS (KEY VALUE ...) and redraw the builder."
  (let ((state (danbooru-builder--settings-state)))
    (cl-loop for (key value) on settings by #'cddr
             do (setf (danbooru-builder-state-gen state)
                      (plist-put (danbooru-builder-state-gen state) key value)))
    (with-current-buffer (danbooru-builder--buffer)
      (danbooru-builder--render))))

(defun danbooru-builder--desc (label value)
  "Menu description: LABEL and the current VALUE highlighted."
  (concat label " " (propertize (format "%s" value) 'face 'transient-value)))

(defun danbooru-builder--short (text)
  "TEXT shortened for a menu line."
  (truncate-string-to-width (if (string-empty-p (or text "")) "-" text) 50 nil nil "…"))

(defun danbooru-builder-set-profile (profile)
  "Use model PROFILE from config.json and its default settings."
  (interactive
   (list (completing-read "Profile: "
                          (danbooru-builder--profiles (danbooru-builder--settings-state))
                          nil t nil nil (danbooru-builder--gen :profile))))
  (danbooru-builder--apply-profile (danbooru-builder--settings-state) profile)
  (danbooru-builder--set-gen))

(defun danbooru-builder-toggle-style ()
  "Switch the prompt style between tags and natural language."
  (interactive)
  (let ((state (danbooru-builder--settings-state)))
    (setf (danbooru-builder-state-style state)
          (if (eq (danbooru-builder-state-style state) 'natural) 'tags 'natural))
    (danbooru-builder--set-gen)))

(defun danbooru-builder--read-int (prompt key min)
  "Read an integer of at least MIN with PROMPT, default the setting KEY."
  (let ((n (read-number prompt (danbooru-builder--gen key))))
    (unless (and (integerp n) (>= n min))
      (user-error "Need a whole number, at least %d" min))
    n))

(defun danbooru-builder-set-width (width)
  "Set the image WIDTH."
  (interactive (list (danbooru-builder--read-int "Width: " :width 64)))
  (danbooru-builder--set-gen :width width))

(defun danbooru-builder-set-height (height)
  "Set the image HEIGHT."
  (interactive (list (danbooru-builder--read-int "Height: " :height 64)))
  (danbooru-builder--set-gen :height height))

(defun danbooru-builder-swap-size ()
  "Swap width and height."
  (interactive)
  (danbooru-builder--set-gen :width (danbooru-builder--gen :height)
                             :height (danbooru-builder--gen :width)))

(defun danbooru-builder-size-preset (size)
  "Set the image size from the config's size presets; SIZE is \"WxH\"."
  (interactive
   (list (completing-read "Size: "
                          (danbooru-builder--cfg (danbooru-builder-state-catalog
                                                  (danbooru-builder--settings-state))
                                                 'size_presets)
                          nil nil nil nil
                          (format "%dx%d" (danbooru-builder--gen :width)
                                  (danbooru-builder--gen :height)))))
  (unless (string-match "\\`[ \t]*\\([0-9]+\\)[ \t]*[xX×][ \t]*\\([0-9]+\\)[ \t]*\\'" size)
    (user-error "Size must be WIDTHxHEIGHT"))
  (danbooru-builder--set-gen :width (string-to-number (match-string 1 size))
                             :height (string-to-number (match-string 2 size))))

(defun danbooru-builder-set-steps (steps)
  "Set the sampling STEPS."
  (interactive (list (danbooru-builder--read-int "Steps: " :steps 1)))
  (danbooru-builder--set-gen :steps steps))

(defun danbooru-builder-set-cfg (cfg)
  "Set the CFG scale."
  (interactive (list (read-number "CFG: " (danbooru-builder--gen :cfg))))
  (unless (> cfg 0) (user-error "CFG must be positive"))
  (danbooru-builder--set-gen :cfg cfg))

(defun danbooru-builder-set-sampler (sampler)
  "Set the SAMPLER."
  (interactive (list (completing-read "Sampler: " danbooru-builder--samplers nil t nil nil
                                      (danbooru-builder--gen :sampler))))
  (danbooru-builder--set-gen :sampler sampler))

(defun danbooru-builder-set-scheduler (scheduler)
  "Set the SCHEDULER."
  (interactive (list (completing-read "Scheduler: " danbooru-builder--schedulers nil t nil nil
                                      (danbooru-builder--gen :scheduler))))
  (danbooru-builder--set-gen :scheduler scheduler))

(defun danbooru-builder-set-seed (seed)
  "Set the first SEED; -1 for one random seed."
  (interactive (list (danbooru-builder--read-int "Seed (-1 random): " :seed -1)))
  (danbooru-builder--set-gen :seed seed))

(defun danbooru-builder-set-seed-end (end)
  "Set the last seed END of a seed range; below the first seed: no range."
  (interactive (list (danbooru-builder--read-int "Last seed (-1 none): " :seed-end -1)))
  (danbooru-builder--set-gen :seed-end end))

(defun danbooru-builder-set-seed-step (step)
  "Set the STEP between the seeds of a range."
  (interactive (list (danbooru-builder--read-int "Seed step: " :seed-step 1)))
  (danbooru-builder--set-gen :seed-step step))

(defun danbooru-builder-random-seed ()
  "Use one random seed per image set, no seed range."
  (interactive)
  (danbooru-builder--set-gen :seed -1 :seed-end -1))

(defun danbooru-builder-set-negative (text)
  "Set the negative prompt TEXT."
  (interactive (list (read-string "Negative prompt: "
                                  (danbooru-builder-state-negative
                                   (danbooru-builder--settings-state)))))
  (setf (danbooru-builder-state-negative (danbooru-builder--settings-state)) (string-trim text))
  (danbooru-builder--set-gen))

(defun danbooru-builder-set-extra (text)
  "Set extra free TEXT appended to the prompt."
  (interactive (list (read-string "Extra text: "
                                  (danbooru-builder-state-extra
                                   (danbooru-builder--settings-state)))))
  (setf (danbooru-builder-state-extra (danbooru-builder--settings-state)) (string-trim text))
  (danbooru-builder--set-gen))

(defun danbooru-builder-set-backend (backend)
  "Generate with BACKEND: \"sd-cli\" (the profile's model) or an sd-server URL."
  (interactive
   (list (completing-read
          "Backend (sd-cli or server URL): "
          (delete-dups
           (seq-remove (lambda (s) (string-blank-p (or s "")))
                       (list "sd-cli" danbooru-server danbooru-local-server
                             (danbooru-builder--cfg (danbooru-builder-state-catalog
                                                     (danbooru-builder--settings-state))
                                                    'server_url))))
          nil nil nil nil (danbooru-builder--gen :backend))))
  (let ((backend (string-trim backend)))
    (unless (or (equal backend "sd-cli") (string-match-p "\\`https?://" backend))
      (user-error "Backend must be sd-cli or an http:// URL"))
    (danbooru-builder--set-gen :backend backend)))

(transient-define-prefix danbooru-builder-settings ()
  "Generation settings of the danbooru builder."
  [["Model"
    ("p" danbooru-builder-set-profile :transient t
     :description (lambda () (danbooru-builder--desc "Profile" (danbooru-builder--gen :profile))))
    ("b" danbooru-builder-set-backend :transient t
     :description (lambda () (danbooru-builder--desc "Backend" (danbooru-builder--gen :backend))))
    ("y" danbooru-builder-toggle-style :transient t
     :description (lambda () (danbooru-builder--desc
                              "Style  " (danbooru-builder-state-style
                                         (danbooru-builder--settings-state)))))]
   ["Size"
    ("W" danbooru-builder-set-width :transient t
     :description (lambda () (danbooru-builder--desc "Width " (danbooru-builder--gen :width))))
    ("H" danbooru-builder-set-height :transient t
     :description (lambda () (danbooru-builder--desc "Height" (danbooru-builder--gen :height))))
    ("z" "Preset" danbooru-builder-size-preset :transient t)
    ("w" "Swap" danbooru-builder-swap-size :transient t)]
   ["Sampling"
    ("t" danbooru-builder-set-steps :transient t
     :description (lambda () (danbooru-builder--desc "Steps    " (danbooru-builder--gen :steps))))
    ("c" danbooru-builder-set-cfg :transient t
     :description (lambda () (danbooru-builder--desc "CFG      " (danbooru-builder--gen :cfg))))
    ("a" danbooru-builder-set-sampler :transient t
     :description (lambda () (danbooru-builder--desc "Sampler  " (danbooru-builder--gen :sampler))))
    ("d" danbooru-builder-set-scheduler :transient t
     :description (lambda () (danbooru-builder--desc "Scheduler" (danbooru-builder--gen :scheduler))))]
   ["Seed"
    ("s" danbooru-builder-set-seed :transient t
     :description (lambda () (danbooru-builder--desc "First" (danbooru-builder--gen :seed))))
    ("e" danbooru-builder-set-seed-end :transient t
     :description (lambda () (danbooru-builder--desc "Last " (danbooru-builder--gen :seed-end))))
    ("i" danbooru-builder-set-seed-step :transient t
     :description (lambda () (danbooru-builder--desc "Step " (danbooru-builder--gen :seed-step))))
    ("r" "Random" danbooru-builder-random-seed :transient t)]]
  ["Text"
   ("n" danbooru-builder-set-negative :transient t
    :description (lambda () (danbooru-builder--desc
                             "Negative" (danbooru-builder--short
                                         (danbooru-builder-state-negative
                                          (danbooru-builder--settings-state))))))
   ("x" danbooru-builder-set-extra :transient t
    :description (lambda () (danbooru-builder--desc
                             "Extra   " (danbooru-builder--short
                                         (danbooru-builder-state-extra
                                          (danbooru-builder--settings-state))))))])

(defvar-keymap danbooru-builder-mode-map
  :doc "Keymap of `danbooru-builder-mode'."
  :parent special-mode-map
  "a" #'danbooru-builder-add
  "A" #'danbooru-builder-add-in-category
  "G" #'danbooru-builder-pick-groups
  "T" #'danbooru-builder-add-text
  "t" #'danbooru-builder-place-text
  "k" #'danbooru-builder-remove
  "C-k" #'danbooru-builder-remove
  "d" #'danbooru-builder-remove
  "RET" #'danbooru-builder-edit
  "M-<up>" #'danbooru-builder-move-up
  "M-<down>" #'danbooru-builder-move-down
  "M-p" #'danbooru-builder-move-up
  "M-n" #'danbooru-builder-move-down
  "m" #'danbooru-builder-mark
  "u" #'danbooru-builder-unmark
  "U" #'danbooru-builder-unmark-all
  "v" #'danbooru-builder-vary
  "x" #'danbooru-builder-toggle-alternative
  "i" #'danbooru-builder-show-alternative-image
  "l" #'danbooru-builder-link
  "P" #'danbooru-builder-add-person
  "e" #'danbooru-builder-edit-person
  "w" #'danbooru-builder-copy-prompt
  "g" #'danbooru-builder-reload
  "s" #'danbooru-builder-settings
  "C-c C-c" #'danbooru-builder-generate
  "C-c C-k" #'danbooru-builder-cancel
  "C-c C-p" #'danbooru-builder-show-variants
  "C-x C-s" #'danbooru-builder-save
  "C-x C-w" #'danbooru-builder-save-as
  "o" #'danbooru-builder-open
  "N" #'danbooru-builder-new
  "E" #'danbooru-builder-export
  "n" #'next-line
  "p" #'previous-line
  "TAB" #'danbooru-builder-next-section
  "<backtab>" #'danbooru-builder-previous-section)

(define-derived-mode danbooru-builder-mode special-mode "Danbooru-Builder"
  "Build an Anima prompt from the tag catalog in `danbooru-builder-directory'.

\\{danbooru-builder-mode-map}"
  (setq truncate-lines nil
        header-line-format '(:eval (danbooru-builder--header-line)))
  (add-hook 'kill-buffer-query-functions #'danbooru-builder--kill-buffer-query nil t)
  (visual-line-mode 1))

;;;###autoload
(defun danbooru-builder--get-buffer ()
  "The builder buffer, set up with a new state on first use."
  (let ((buf (get-buffer-create "*danbooru-builder*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'danbooru-builder-mode)
        (danbooru-builder-mode))
      (unless danbooru-builder--state
        (danbooru-builder--install (danbooru-builder--new-state (danbooru-builder--catalog))
                                   nil)))
    buf))

;;;###autoload
(defun danbooru-builder-legacy ()
  "Open the prompt builder, creating it on first use."
  (interactive)
  (pop-to-buffer-same-window (danbooru-builder--get-buffer)))

;;; ── Source-connected compiler projection ──

(autoload 'danbooru-builder-import "danbooru-builder-source" nil t)

;;;###autoload
(defun danbooru-builder ()
  "Open the legacy Danbooru builder."
  (interactive)
  (danbooru-builder-legacy))

;;;###autoload
(defun danbooru-builder-open (file)
  "Open a .danbooru FILE, or import a legacy .dbb FILE."
  (interactive (list (read-file-name "Open prompt or import .dbb: " nil nil t)))
  (if (string-suffix-p ".dbb" file) (danbooru-builder-import file)
    (find-file file)))

(provide 'danbooru-builder)
;;; danbooru-builder.el ends here
