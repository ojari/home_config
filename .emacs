(show-paren-mode t)
(menu-bar-mode -1)
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
  gnus-select-method '(nnml "")
)

(setq gdb-many-windows nil)

;;(setq screen-width 120
;;      screen-height 75)

;;(if (string-equal user-login-name "jari")
;;    (setq screen-width 90
;;	  screen-height 60))

;(set-face-attribute 'default nil :font "Fira Code Retina" :height 120)
(set-face-attribute 'default nil :font "FiraCode Nerd Font Mono Ret" :height 120)
;(set-face-attribute 'default nil :font "FiraCode Nerd Font Mono")

(add-to-list 'load-path "/home/jari")
;; (require 'tomelr)
;; (require 'ox-hugo)
;; (require 'ls-lisp)

(setq inhibit-startup-screen t
      visible-bell 1
      system-time-locale "fi"
      frame-title-format "emacs - %b"
      ;;default-frame-alist '((top . 0)
;;			    (left . 0)
;;			    (width . 120)
;;			    (height . screen-height))
					;(font . "-unknown-Hack-normal-normal-normal-*-16-*-*-*-m-0-iso10646-1"))
			    ;;(font . "-outline-Fira Code Retina-regular-normal-normal-*-17-*-*-*-c-0-iso8859-1"))
      
      w32-get-true-file-attributes nil
      tab-stop-list (number-sequence 4 200 4)
      tab-width 4
      user-full-name "Jari Ojanen"
      make-backup-files nil
      ls-lisp-dirs-first t
      ls-lisp-ignore-case t
      ls-lisp-verbosity nil
      ls-lisp-use-insert-directory-program nil
      calendar-week-start-day 1
      )

(fset 'yes-or-no-p 'y-or-n-p)

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

(use-package vertico
  :custom
  (vertico-count 20)
  (completion-ignore-case t)
  ;;(vertico-resize t)
  :bind
  (("C-c n f" . org-roam-node-find)
   ("C-c n g" . org-roam-ui-open)        ;; Generate the Org-roam graph
   ("C-c n l" . org-roam-buffer-toggle)  ;; Toggle the Org-roam buffer
   ("C-c n i" . org-roam-node-insert)    ;; Insert an Org-roam node
   ;; ("C-c n o" . ido-open-org-roam-node)
   ("C-c n s" . org-roam-db-sync))
  
  :init
  (vertico-mode))

;; (setq completion-styles '(basic substring partial-completion flex)
;;       completion-ignore-case t
;;       read-buffer-completion-ignore-case t
;;       read-file-name-completion-ignore-case t)


(use-package orderless
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package doom-modeline
  :ensure t
  :init
  (doom-modeline-mode 1)
  :custom
  ((doom-modeline-height 15)
   (doom-modeline-icon t)))

(use-package projectile
  :ensure t
  :init
  (projectile-mode +1)
  :config
  ;; Optionally set Projectile to use the default project search method
  (setq projectile-completion-system 'default)
  ;; Optionally define a keymap prefix for Projectile commands
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map))

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

;(add-hook 'org-mode-hook
;	  '(lambda ()
;	     (local-unset-key "C-j")))

;;------------------------------------------------------------------------------
(load-theme 'wombat)
;(load-theme 'zenburn t)
;(load-theme 'tango-dark)

(if (eq system-type 'windows-nt)
    (cd "c:/home"))

;;------------------------------------------------------------------------------
(defun tunnit ()
  (interactive)
  (let ((previous-week (- (string-to-number (format-time-string "%W"))
			  1))
	(days '("ma" "ti" "ke" "to" "pe")))
    (insert (concat "WK" (number-to-string previous-week)))
    (newline)
    (dolist (d days nil)
      (progn
	(insert (concat " - " d " 7.5"))
	(newline)))
    ))

;;------------------------------------------------------------------------------
(defun node-repl ()
  (interactive)
  (run-clojure "java -cp cljs.jar clojure.main repl.clj"))

;;------------------------------------------------------------------------------
(defun magit-ignore-whitespace ()
  (interactive)
  (add-to-list 'magit-diff-options "-w")
  (magit-refresh))


;;------------------------------------------------------------------------------
;; (load-library "bookmark")
;; (defun ido-bookmarks ()
;;   (interactive)
;;   (let ((bmark (ido-completing-read "Bookmark:" (bookmark-all-names) nil t)))
;;     (bookmark-jump bmark)
;;     ))

(defun ido-m-x ()
  (interactive)
  (call-interactively
   (intern
    (ido-completing-read
     "M-x "
     (all-completions "" obarray 'commandp)))))

(defun org-roam-get-file-by-title (title)
  "Return the file path of the Org-roam node with the given TITLE."
  (let ((node (cl-find-if (lambda (n)
                            (string= title (org-roam-node-title n)))
                          (org-roam-node-list))))
    (when node
      (org-roam-node-file node))))

(setq org-roam-buffer-window-parameters '((no-delete-other-windows . t)))

(defun ido-open-org-roam-node ()
  (interactive)
  (find-file
   (org-roam-get-file-by-title
    (ido-completing-read
     "Node:"
     (mapcar #'org-roam-node-title (org-roam-node-list))
     nil
     t))))


(defun my-compile-parent (path)
  (let ((default-directory (substring path 0 -5)))
    (compile "make -k")))

(defun my-compile ()
  (interactive)
  (cond
   ((equal major-mode 'java-mode) (message "java"))
   ((equal major-mode 'c-mode)
    (let ((path (file-name-directory (buffer-file-name))))
      (if (string-match "/src/$" path)
	  (my-compile-parent path)
	(compile "ninja"))))
   ((equal major-mode 'c++-mode)  (compile "make -k"))
   ((equal major-mode 'emacs-lisp-mode)
    (byte-compile-file (buffer-file-name)))
   ((equal major-mode 'python-mode)
    (compile (concat "python3 " (buffer-file-name))))
   (t
    (message "unknown mode")
    )))

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
	 :auto-preamble t
	 )
	("org-roam"
	 :base-directory "~/org-roam/"
	 :base-extension "org"
	 :publishing-directory "~/tmp/"
	 :recursive t
	 :publishing-function org-html-publish-to-html
	 :headline-levels 4             ; Just the default for this project.
	 :auto-preamble t
	 )
	))

(org-babel-do-load-languages
 'org-babel-load-languages
 '(
   (plantuml . t)
   (dot . t)
   (C . t)))

(setq org-plantuml-jar-path (expand-file-name "~/plantuml.jar")
      org-mobile-directory "/tmp/org-mobile"
      org-time-stamp-custom-formats '("<%m/%d/%y %a>" . "<%d/%m %a %H:%M>"))

(defun my-org-confirm-babel-evaluate (lang body)
  (not (string= lang "plantuml")))  ; don't ask for plantuml

(setq org-confirm-babel-evaluate 'my-org-confirm-babel-evaluate)

(setq org-roam-completion-system 'vertico
      org-roam-completion-everywhere t
      org-roam-directory "~/org-roam")

(setq org-roam-capture-templates
      '(
	("a" "abb" plain (file "~/org-roam/abb/templates/stuff.org")
	 :target (file+head "abb/%<%Y%m%d>-${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("b" "study" plain (file "~/org-roam/templates/learn.org")
	 :target (file+head "study/%<%Y%m%d>-${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("m" "my" plain (file "~/org-roam/templates/my.org")
	 :target (file+head "my/%<%Y%m%d>-${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("s" "sport" plain (file "~/org-roam/templates/sport.org")
	 :target (file+head "sport/%<%Y%m%d>-${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	)
      )
;(setq org-roam-node-completion-function
;      (lambda () (org-roam-completion--ido #'org-roam-node-read)))


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
;; (defun mbed-flash ()
;;   (interactive)
;;   (copy-file "BUILD/blinky.bin" "D:/"))

;; (defun arm-gdb ()
;;   (interactive)
;;   (setq gdb-many-windows nil)
;;   (gdb "/mnt/bin/gcc-arm/bin/arm-none-eabi-gdb -i=mi bin/meas.elf"))


(defun my-region-transfer ()
  (interactive)
  (if (region-active-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
	(other-window 1)
	(insert text)
	(insert "\n")
	(other-window 1))
    (message "No region active!")))

;;------------------------------------------------------------------------------
(load-library "dired")
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

(define-key dired-mode-map "e" 'dired-ediff-files)

;;------------------------------------------------------------------------------
(load-library "~/project_config.el")
(load-library "~/keymap.el")

;;------------------------------------------------------------------------------
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(browse-url-chrome-program "C:/Program Files (x86)/Google/Chrome/Application/chrome")
 '(browse-url-firefox-program "c:/Program Files/Firefox/firefox")
 '(custom-safe-themes
   '("8aebf25556399b58091e533e455dd50a6a9cba958cc4ebb0aab175863c25b9a4"
     "afbb40954f67924d3153f27b6d3399df221b2050f2a72eb2cfa8d29ca783c5a8"
     default))
 '(grep-find-ignored-directories '(".src" ".svn" ".git"))
 '(grep-find-ignored-files
   '(".#*" "*.o" "*~" "*.bin" "*.so" "*.a" "*.ln" "*.elc" "*.class"
     "*.lib" "*.lo" "*.la" "*.pg" "*.pyc" "*.pyo"))
 '(grep-highlight-matches t)
 '(ls-lisp-verbosity nil)
 '(magit-diff-arguments '("--stat" "--no-ext-diff" "-w"))
 '(magit-fetch-arguments nil)
 '(org-export-with-broken-links 'mark)
 '(package-selected-packages
   '(avy copilot-chat csharp-mode doom-modeline elfeed flycheck
	 imenu-anywhere magit orderless org-roam org-roam-ui ox-hugo
	 projectile vertico which-key)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
