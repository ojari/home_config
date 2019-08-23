(show-paren-mode t)
(menu-bar-mode -1)
(if window-system
    (progn
      (setq tramp-default-method "plink")
      (tool-bar-mode -1))
  (progn
    (xterm-mouse-mode)))


(setq gdb-many-windows nil)

(setq screen-width 120
      screen-height 55)

(if (string-equal user-login-name "jari")
    (setq screen-width 90
	  screen-height 60))

(require 'ls-lisp)

(setq inhibit-startup-screen t
      visible-bell 1
      system-time-locale "fi"
      frame-title-format "emacs - %b"
      default-frame-alist '((top . 0)
			    (left . 0)
			    (width . 120)
			    (height . screen-height)
			    (font . "-unknown-Hack-normal-normal-normal-*-16-*-*-*-m-0-iso10646-1"))
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

;; Keyboard mappings
;;

(global-set-key (kbd "M-[ a") 'windmove-up)
(global-set-key (kbd "M-[ b") 'windmove-down)
(global-set-key (kbd "M-[ c") 'windmove-right)
(global-set-key (kbd "M-[ d") 'windmove-left)


(fset 'yes-or-no-p 'y-or-n-p)

(require 'package)
;(add-to-list 'package-archives
;             '("melpa" . "http://melpa.org/packages/") t)
(add-to-list 'package-archives
             '("melpa-stable" . "http://stable.melpa.org/packages/") t)

(package-initialize)

;(require 'helm-config)
;(global-set-key (kbd "M-x")     'helm-M-x)
;(global-set-key (kbd "C-x r b") 'helm-filtered-bookmarks)
;(global-set-key (kbd "C-x C-f") 'helm-find-files)

(ido-mode t)
(ido-everywhere t)
(ido-vertical-mode t)
(setq ido-enable-flex-matching t)

(which-key-mode)

(load-library "~/template.el")

(add-hook 'c-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

(add-hook 'c++-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

;;------------------------------------------------------------------------------
(load-theme 'wombat)
;(load-theme 'zenburn t)
;(load-theme 'tango-dark)

(if (eq system-type 'windows-nt)
    (cd "c:/home"))


;;------------------------------------------------------------------------------
(defun node-repl ()
  (interactive)
  (run-clojure "java -cp cljs.jar clojure.main repl.clj"))

;;------------------------------------------------------------------------------
(defun magit-ignore-whitespace ()
  (interactive)
  (add-to-list 'magit-diff-options "-w")
  (magit-refresh))


(load-library "bookmark")
;;------------------------------------------------------------------------------
(defun ido-bookmarks ()
  (interactive)
  (let ((bmark (ido-completing-read "Bookmark:" (bookmark-all-names) nil t)))
    (bookmark-jump bmark)
    ))

(defun ido-m-x ()
  (interactive)
  (call-interactively
   (intern
    (ido-completing-read
     "M-x "
     (all-completions "" obarray 'commandp)))))


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
   (t  (message "unknown mode"))))

;;------------------------------------------------------------------------------
;; org-mode
(setq org-publish-project-alist
      '(
	("github"
	 :base-directory "~/j-a-r-i.github.io/"
	 :base-extension "org"
	 :publishing-directory "~/j-a-r-i.github.io/"
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
      org-time-stamp-custom-formats '("<%m/%d/%y %a>" . "<%d/%m %a %H:%M>"))

(defun my-org-confirm-babel-evaluate (lang body)
  (not (string= lang "plantuml")))  ; don't ask for plantuml

(setq org-confirm-babel-evaluate 'my-org-confirm-babel-evaluate)

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
(defun mbed-flash ()
  (interactive)
  (copy-file "BUILD/blinky.bin" "D:/"))

(defun arm-gdb ()
  (interactive)
  (setq gdb-many-windows nil)
  (gdb "/mnt/bin/gcc-arm/bin/arm-none-eabi-gdb -i=mi bin/meas.elf"))


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
(load-library "~/keymap.el")
(load-library "~/feed.el")

;;------------------------------------------------------------------------------
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(browse-url-chrome-program "C:/Program Files (x86)/Google/Chrome/Application/chrome")
 '(browse-url-firefox-program "c:/Program Files/Firefox/firefox")
 '(custom-safe-themes
   (quote
    ("8aebf25556399b58091e533e455dd50a6a9cba958cc4ebb0aab175863c25b9a4" "afbb40954f67924d3153f27b6d3399df221b2050f2a72eb2cfa8d29ca783c5a8" default)))
 '(grep-find-ignored-directories (quote (".src" ".svn" ".git")))
 '(grep-find-ignored-files
   (quote
    (".#*" "*.o" "*~" "*.bin" "*.so" "*.a" "*.ln" "*.elc" "*.class" "*.lib" "*.lo" "*.la" "*.pg" "*.pyc" "*.pyo")))
 '(grep-highlight-matches t)
 '(ls-lisp-verbosity nil)
 '(magit-diff-arguments (quote ("--stat" "--no-ext-diff" "-w")))
 '(magit-fetch-arguments nil)
 '(package-selected-packages
   (quote
    (csharp-mode elfeed imenu-anywhere magit ido-vertical-mode avy which-key))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
