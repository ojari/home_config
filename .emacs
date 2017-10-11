(show-paren-mode t)
(menu-bar-mode -1)
(if window-system
    (progn
      (tool-bar-mode -1)))

(setq gdb-many-windows t)

(setq tramp-default-method "plink")

(setq screen-width 120
      screen-height 55)

(if (string-equal user-login-name "jari")
    (setq screen-width 90
	  screen-height 60))

(setq inhibit-startup-screen t
      visible-bell 1
      frame-title-format "emacs - %b"
      default-frame-alist '((top . 0)
			    (left . 0)
			    (width . 120)
			    (height . screen-height))
      w32-get-true-file-attributes nil
      tab-stop-list (number-sequence 4 200 4)
      tab-width 4
      user-full-name "Jari Ojanen"
      make-backup-files nil
      ls-lisp-dirs-first t
      ls-lisp-ignore-case t
      ls-lisp-verbosity nil
      )

;; Keyboard mappings
;;
(global-set-key [f11] 'kill-this-buffer)
(global-set-key [f12] 'magit-status)

(fset 'yes-or-no-p 'y-or-n-p)

(require 'package)
;(add-to-list 'package-archives
;             '("melpa" . "http://melpa.org/packages/") t)
(add-to-list 'package-archives
             '("melpa-stable" . "http://stable.melpa.org/packages/") t)

(package-initialize)

;(require 'helm-config)
(global-set-key (kbd "M-x")     'helm-M-x)
(global-set-key (kbd "C-x r b") 'helm-filtered-bookmarks)
(global-set-key (kbd "C-x C-f") 'helm-find-files)

(add-hook 'c-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

(add-hook 'c++-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

;;------------------------------------------------------------------------------
(eval-after-load "dired"
  '(progn
     (define-key dired-mode-map (kbd "<left>") 'dired-up-directory)
     (define-key dired-mode-map (kbd "<right>") 'dired-find-file)))


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

(setq org-plantuml-jar-path
      (expand-file-name "~/plantuml.jar"))

(defun my-org-confirm-babel-evaluate (lang body)
  (not (string= lang "plantuml")))  ; don't ask for plantuml

(setq org-confirm-babel-evaluate 'my-org-confirm-babel-evaluate)


;;------------------------------------------------------------------------------
(defun mbed-flash ()
  (interactive)
  (copy-file "BUILD/blinky.bin" "D:/"))

(defun mbed-gdb ()
  (interactive)
  (setq gdb-many-windows t)
  (gdb "arm-none-eabi-gdb -i=mi BUILD/blinky.elf"))

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
 '(magit-diff-arguments (quote ("--stat" "--no-ext-diff" "-w")))
 '(package-selected-packages
   (quote
    (elfeed twittering-mode helm-projectile projectile helm zenburn-theme magit))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
