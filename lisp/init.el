(show-paren-mode t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(set-fringe-mode 10)
(if window-system
    (progn
      (setq tramp-default-method "plink")
      (tool-bar-mode -1)
      (tooltip-mode -1))
  (progn
    (xterm-mouse-mode)))

(setq
  nnmail-spool-file "Z:/backup/.../thunderbird/.../Mail/LocalFolders/InBox"
  gnus-select-method '(nnml ""))

(setq gdb-many-windows nil)

(set-face-attribute 'default nil :font "FiraCode Nerd Font Mono Ret" :height 120)

(add-to-list 'load-path (getenv "HOME"))

(setq system-time-locale "fi"
      frame-title-format "emacs - %b"
      w32-get-true-file-attributes nil
      tab-stop-list (number-sequence 4 200 4)
      tab-width 4
      user-full-name "Jari Ojanen"
      compilation-scroll-output t
      ls-lisp-dirs-first t
      ls-lisp-ignore-case t
      ls-lisp-verbosity nil
      ls-lisp-use-insert-directory-program nil
      calendar-week-start-day 1
      minibuffer-message-timeout 0
      )

(require 'package)

(setq package-check-signature nil)
(add-to-list 'package-archives
             '("melpa" . "http://melpa.org/packages/") t)
(add-to-list 'package-archives
	     '("gnu"   . "https://elpa.gnu.org/packages/") t)
;(add-to-list 'package-archives
;             '("melpa-stable" . "http://stable.melpa.org/packages/") t)
(package-initialize)


;(ido-mode t)
;(ido-everywhere t)
;;(ido-vertical-mode t)
;;(setq ido-enable-flex-matching t
;;      ido-everywhere t)

(define-prefix-command 'my-jmenu)

(use-package emacs
  :ensure nil
  :custom
  (inhibit-startup-message t)
  (initial-scratch-message "")
  (create-lockfiles nil)   ; No lock files
  (make-backup-files nil)  ; No backup files
  (use-short-answers t)
  (visible-bell 1)
  :config
  :init
  (with-current-buffer (get-buffer-create "*scratch*")
    (insert (format ";;
;; ███████╗███╗   ███╗ █████╗  ██████╗███████╗
;; ██╔════╝████╗ ████║██╔══██╗██╔════╝██╔════╝
;; █████╗  ██╔████╔██║███████║██║     ███████╗
;; ██╔══╝  ██║╚██╔╝██║██╔══██║██║     ╚════██║
;; ███████╗██║ ╚═╝ ██║██║  ██║╚██████╗███████║
;; ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝
;;
;;   Loading time : %s
;;   Packages     : %s
;;
"
                    (emacs-init-time)
                    (number-to-string (length package-activated-list)))))  
  ;; Ibuffer filters
  (setq ibuffer-saved-filter-groups
        '(("default"
           ("C++" (or
                        (mode . c-mode)
                        (mode . c++-mode)))
           ("org"     (or
                       (mode . org-mode)
                       (name . "^\\*Org Src")
                       (name . "^\\*Org Agenda\\*$")))
           ("emacs"   (or
                       (name . "^\\*scratch\\*$")
                       (name . "^\\*Messages\\*$")
                       (name . "^\\*Warnings\\*$")
                       (name . "^\\*Shell Command Output\\*$")
                       (name . "^\\*Async-native-compile-log\\*$")))
           ("ediff"   (name . "^\\*[Ee]diff.*"))
           ("vc"      (name . "^\\*vc-.*"))
           ("dired"   (mode . dired-mode))
           ("terminal" (or
                        (mode . term-mode)
                        (mode . shell-mode)
                        (mode . eshell-mode)))
           ("help"    (or
                       (name . "^\\*Help\\*$")
                       (name . "^\\*info\\*$"))))))

  (add-hook 'ibuffer-mode-hook
            (lambda ()
              (ibuffer-switch-to-saved-filter-groups "default")))
  (setq ibuffer-show-empty-filter-groups nil) ; don't show empty groups
  )

;;; | icomplete
(use-package icomplete
  :bind (:map icomplete-minibuffer-map
              ("C-k" . icomplete-forward-completions)
              ("C-i" . icomplete-backward-completions)
              ("C-v" . icomplete-vertical-toggle)
              ("RET" . icomplete-force-complete-and-exit)
              ("C-j" . exit-minibuffer)) ;; So we can exit commands like `multi-file-replace-regexp-as-diff'
  :hook
  (after-init-hook . (lambda ()
                       (fido-mode -1)
                       (icomplete-vertical-mode 1)))
  :config
  (setq icomplete-delay-completions-threshold 0)
  (setq icomplete-compute-delay 0)
  (setq icomplete-show-matches-on-no-input t)
  (setq icomplete-hide-common-prefix nil)
  (setq icomplete-prospects-height 10)
  (setq icomplete-separator " . ")
  (setq icomplete-with-completion-tables t)
  (setq icomplete-in-buffer t)
  (setq icomplete-max-delay-chars 0)
  (setq icomplete-scroll t))

;;; │ MINIBUFFER
(use-package minibuffer
  :ensure nil
  :custom
  (completion-auto-help t)
  (completion-auto-select 'second-tab)
  (completion-eager-update t) ;; EMACS-31
  (completion-ignore-case t)
  (completion-show-help nil)
  (completion-styles '(partial-completion flex initials))
  (completions-format 'one-column)
  (completions-max-height nil)
  (completions-sort 'historical)
  (enable-recursive-minibuffers t)
  (read-buffer-completion-ignore-case t)
  (read-file-name-completion-ignore-case t)
)

;;; | org
(use-package org
  :ensure nil
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((plantuml . t)
     (dot . t)
     (python . t)
     (shell . t)
     (C . t)))

  (defun my/org-confirm-babel-evaluate (lang body)
    (not (or (string= lang "plantuml")
	     (string= lang "python")
	     (string= lang "dot"))))  ; don't ask for these modes
  (setq org-confirm-babel-evaluate 'my/org-confirm-babel-evaluate)
  
  )

;;; | org-roam
(use-package org-roam
  :ensure t
  :config
  (define-key org-mode-map (kbd "C-j") 'my-jmenu)
  :custom
  ;(org-roam-completion-system 'vertico)
  (org-roam-completion-everywhere t)
  (org-roam-directory "~/org-roam"))

;;; | vertico
;; (use-package vertico
;;   :ensure t
;;   :custom
;;   (vertico-count 20)
;;   (completion-ignore-case t)
;;   ;;(vertico-resize t)
;;   :bind
;;   (("C-c n f" . org-roam-node-find)
;;    ("C-c n a" . org-agenda)
;;    ("C-c n g" . org-roam-ui-open)        ;; Generate the Org-roam graph
;;    ("C-c n l" . org-roam-buffer-toggle)  ;; Toggle the Org-roam buffer
;;    ("C-c n i" . org-roam-node-insert)    ;; Insert an Org-roam node
;;    ;; ("C-c n o" . ido-open-org-roam-node)
;;    ("C-c n s" . org-roam-db-sync))
  
;;   :init
;;   (vertico-mode))

;; (setq completion-styles '(basic substring partial-completion flex)
;;       completion-ignore-case t
;;       read-buffer-completion-ignore-case t
;;       read-file-name-completion-ignore-case t)

;;; | orderless
;; (use-package orderless
;;   :ensure t
;;   :custom
;;   (completion-styles '(orderless))
;;   (completion-category-defaults nil)
;;   (completion-category-overrides '((file (styles partial-completion)))))


;; (use-package epa
;;   :ensure nil  ;; epa is built-in, so no need to install
;;   :config
;;   (epa-file-enable)  ;; Enable automatic decryption/encryption of .gpg files
;;   (setq epa-pinentry-mode 'loopback))  ;; Optional: use Emacs minibuffer for passphrase

;; (use-package gptel
;;   :config
;;   (setq gptel-backend
;;         (gptel-make-ollama "Ollama"
;;           :host "localhost:11434"
;;           :stream t
;; 	  :models '(deepseek-coder:6.7b))
;; 	gptel-model "deepseek-coder:6.7b")
;;   )
;; (setq gptel-model "deepseek-coder:6.7b")

;; (use-package doom-modeline
;;   :ensure t
;;   :init
;;   (doom-modeline-mode 1)
;;   :custom
;;   ((doom-modeline-height 15)
;;    (doom-modeline-icon t)))

;; (use-package doom-themes
;;   :ensure t
;;   :config
;;   ;; Global settings (defaults)
;;   (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
;;         doom-themes-enable-italic t) ; if nil, italics is universally disabled
;;   (load-theme 'wombat t)

;;   ;; Enable flashing mode-line on errors
;;   (doom-themes-visual-bell-config)
;;   ;; Enable custom neotree theme (all-the-icons must be installed!)
;;   (doom-themes-neotree-config)
;;   ;; or for treemacs users
;;   (setq doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
;;   (doom-themes-treemacs-config)
;;   ;; Corrects (and improves) org-mode's native fontification.
;;   (doom-themes-org-config))

;; (use-package projectile
;;   :ensure t
;;   :init
;;   (projectile-mode +1)
;;   :custom
;;   (projectile-generic-command "rg --files --hidden")
;;   (projectile-indexing-method 'hybrid)
;;   (projectile-enable-caching t)
;;   :config
;;   ;; Optionally set Projectile to use the default project search method
;;   (setq projectile-completion-system 'default)
;;   ;; Optionally define a keymap prefix for Projectile commands
;;   (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map))

(require 'project)

(setq vertico-sort-function
      (lambda (candidates)
        (sort candidates #'string<)))

(use-package which-key
  :config
  (which-key-mode))

(add-hook 'c-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

(add-hook 'c++-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

(add-hook 'org-mode-hook
	  '(lambda ()
	     (visual-line-mode 1)))

;;------------------------------------------------------------------------------
;(load-theme 'wombat)
;(load-theme 'zenburn t)
(load-theme 'tango-dark)

;; (if (eq system-type 'windows-nt)
;;     (cd (getenv "HOME")))

;;------------------------------------------------------------------------------
(defun node-repl ()
  (interactive)
  (run-clojure "java -cp cljs.jar clojure.main repl.clj"))

;;------------------------------------------------------------------------------
(defun magit-ignore-whitespace ()
  (interactive)
  (add-to-list 'magit-diff-options "-w")
  (magit-refresh))


(setq org-roam-buffer-window-parameters '((no-delete-other-windows . t))
      org-startup-with-inline-images t
      org-startup-with-latex-preview nil
      org-cycle-hide-drawer-startup t)
(setq org-link-frame-setup
      '((file . find-file)))  ;; instead of find-file-other-window


;;------------------------------------------------------------------------------
;; org-mode
(setq org-publish-project-alist
      '(
	("github"
	 :base-directory "~/ojari.github.io/"
	 :base-extension "org"
	 :publishing-directory "~/ojari.github.io/"
	 :recursive t
	 :publishing-function org-html-publish-to-html
	 :headline-levels 4             ; Just the default for this project.
	 :auto-preamble t)
	("org-roam"
	 :base-directory "~/org-roam/"
	 :base-extension "org"
	 :publishing-directory "~/tmp/"
	 :recursive t
	 :publishing-function org-html-publish-to-html
	 :headline-levels 4             ; Just the default for this project.
	 :section-numbers nil
	 :with-author: nil
	 :with-toc nil
	 :time-stamp-file nil
         :html-head "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\" />"
         :html-preamble nil
         :html-postamble nil)
	))

;;(setq org-babel-shell-names '("pwsh"))
;;(setq shell-file-name "C:/Program Files/PowerShell/7/pwsh.exe")

(setq explicit-shell-file-name shell-file-name)

(setq org-plantuml-jar-path (expand-file-name "/usr/plantuml.jar")
      org-mobile-directory "/tmp/org-mobile"
      org-time-stamp-custom-formats '("<%m/%d/%y %a>" . "<%d/%m %a %H:%M>")
      org-agenda-files (directory-files-recursively "~/org-roam" "\\.org$")
      org-agenda-start-with-clockreport-mode t
      org-export-coding-system 'utf-8
      )

(setq org-agenda-files
      (let* ((directory "~/org-roam")
	     (file-list (directory-files-recursively directory "task.*\\.org$")) ; Get all files
	     (additional-files '("~/org-roam/sport/grifk.org"
				 "~/org-roam/sport/esle_lentis.org"
				 "~/org-roam/sport/aikido.org"
				 "~/org-roam/schedule.org")))
	;; Append additional files to the file list
	(append file-list additional-files)))
	

;;(prefer-coding-system 'utf-8)

(setq org-roam-completion-system 'vertico
      org-roam-completion-everywhere t
      org-roam-directory "~/org-roam")

;(setq org-roam-node-completion-function
;      (lambda () (org-roam-completion--ido #'org-roam-node-read)))

(defun my/org-roam-links ()
  "Use Vertico to select a forward or backward link related to the current Org-roam note, without duplicates."
  (interactive)
  (let* ((node (org-roam-node-at-point))
         (node-id (org-roam-node-id node))
         ;; Backlinks: notes that link to this one
         (backlinks
          (org-roam-db-query
           [:select [nodes:title nodes:file nodes:id]
            :from links
            :left-join nodes
            :on (= links:source nodes:id)
            :where (= links:dest $s1)]
           node-id))
         ;; Forward links: notes this one links to
         (forward-links
          (org-roam-db-query
           [:select [nodes:title nodes:file nodes:id]
            :from links
            :left-join nodes
            :on (= links:dest nodes:id)
            :where (= links:source $s1)]
           node-id))
         ;; Combine and annotate
         (combined
          (append
           (mapcar (lambda (row)
                     (list :title (nth 0 row)
                           :file (nth 1 row)
                           :id (nth 2 row)
                           :direction 'backward))
                   backlinks)
           (mapcar (lambda (row)
                     (list :title (nth 0 row)
                           :file (nth 1 row)
                           :id (nth 2 row)
                           :direction 'forward))
                   forward-links)))
         ;; Remove duplicates by ID
         (unique-links
          (let ((seen (make-hash-table :test #'equal)))
            (seq-filter
             (lambda (item)
               (let ((id (plist-get item :id)))
                 (unless (gethash id seen)
                   (puthash id t seen)
                   t)))
             combined)))
         ;; Format for completion
         (choices
          (mapcar (lambda (item)
                    (cons (format "%s %s"
                                  (if (eq (plist-get item :direction) 'backward) "←" "→")
                                  (plist-get item :title))
                          (plist-get item :file)))
                  unique-links))
         (selected (completing-read "Links: " choices)))
    (find-file (cdr (assoc selected choices)))))


;;------------------------------------------------------------------------------
;; week numbers to calendar

(copy-face font-lock-constant-face 'calendar-iso-week-face)
(set-face-attribute 'calendar-iso-week-face nil
                    :height 0.6)
(setq calendar-intermonth-text
      '(propertize
        (format "%2d"
                (car
                 (calendar-iso-from-absolute
                  (calendar-absolute-from-gregorian (list month day year)))))
        'font-lock-face 'calendar-iso-week-face))

;;------------------------------------------------------------------------------
(defun my/region-transfer ()
  (interactive)
  (if (region-active-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
	(other-window 1)
	(insert text)
	(insert "\n")
	(other-window 1))
    (message "No region active!")))

;;------------------------------------------------------------------------------
;;; | dired
(use-package dired
  :ensure nil
  :bind
  (:map dired-mode-map
        ("e" . my/dired-ediff-files)
        ("j" . dired-up-directory)
        ("l" . dired-find-file)
        ("k" . dired-next-line)
        ("i" . dired-previous-line)
        ("q" . quit-window))
  :init
  (defun dired-ediff-files ()
    (interactive)
    (let ((files (dired-get-marked-files))
          (wnd (current-window-configuration)))
      (if (= (length files) 2)
	  (progn
	    (message (car files))
            (ediff-files (car files)
			 (cadr files))
	    (add-hook 'ediff-aft1er-quit-hook-internal
                      (lambda ()
			(setq ediff-after-quit-hook-internal nil)
			(set-window-configuration wnd))))
	(error "no more than 2 files should be marked"))))
  )

;;------------------------------------------------------------------------------
(load-library "~/home_config/lisp/project_config.el")
(load-library "~/home_config/lisp/keymap.el")

;;------------------------------------------------------------------------------
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(browse-url-chrome-program "C:/Program Files (x86)/Google/Chrome/Application/chrome")
 '(browse-url-firefox-program "c:/Program Files/Firefox/firefox")
 '(custom-safe-themes
   '("e8bd9bbf6506afca133125b0be48b1f033b1c8647c628652ab7a2fe065c10ef0"
     "4594d6b9753691142f02e67b8eb0fda7d12f6cc9f1299a49b819312d6addad1d"
     "8aebf25556399b58091e533e455dd50a6a9cba958cc4ebb0aab175863c25b9a4"
     "afbb40954f67924d3153f27b6d3399df221b2050f2a72eb2cfa8d29ca783c5a8"
     default))
 '(dashboard-bookmarks-item-format "%s - %s")
 '(dashboard-bookmarks-show-base nil)
 '(grep-find-ignored-directories '(".src" ".svn" ".git"))
 '(grep-find-ignored-files
   '(".#*" "*.o" "*~" "*.bin" "*.so" "*.a" "*.ln" "*.elc" "*.class"
     "*.lib" "*.lo" "*.la" "*.pg" "*.pyc" "*.pyo"))
 '(grep-highlight-matches t)
 '(ls-lisp-verbosity nil)
 '(magit-diff-arguments '("--stat" "--no-ext-diff" "-w"))
 '(magit-fetch-arguments nil)
 '(org-agenda-files
   '("c:/home/jari/org-roam/sport/grifk.org"
     "c:/home/jari/org-roam/my/schedule.org"))
 '(org-export-with-broken-links 'mark)
 '(package-selected-packages '(magit org-roam)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

