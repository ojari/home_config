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

(setq gdb-many-windows nil)

(set-face-attribute 'default nil :font "FiraCode Nerd Font Mono Ret" :height 120)

(add-to-list 'load-path (getenv "HOME"))

(setq inhibit-startup-screen t
      visible-bell 1
      system-time-locale "fi"
      frame-title-format "%b"
      w32-get-true-file-attributes nil
      tab-stop-list (number-sequence 4 200 4)
      tab-width 4
      user-full-name "Jari Ojanen"
      make-backup-files nil
      compilation-scroll-output t
      ls-lisp-dirs-first t
      ls-lisp-ignore-case t
      ls-lisp-verbosity nil
      ls-lisp-use-insert-directory-program nil
      calendar-week-start-day 1
      minibuffer-message-timeout 0)

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


(define-prefix-command 'my-jmenu)

(use-package org-roam
  :config
  (define-key org-mode-map (kbd "C-j") 'my-jmenu)
  :custom
  (org-roam-completion-system 'vertico)
  (org-roam-completion-everywhere t)
  (org-roam-directory "~/org-roam"))

(use-package org-modern
  :ensure t
  )
  

(use-package vertico
  :custom
  (vertico-count 20)
  (completion-ignore-case t)
  ;;(vertico-resize t)
  :bind
  (("C-c n f" . org-roam-node-find)
   ("C-c n a" . org-agenda)
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

(use-package consult
  :ensure t
  :bind
  (("C-s" . consult-line))
  ;;:custom
  ;;(consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator /   --smart-case --no-heading --with-filename --line-number --search-zip --glob '!*.xml' --glob '!*.txt'")
  )

(use-package epa
  :ensure nil  ;; epa is built-in, so no need to install
  :config
  (epa-file-enable)  ;; Enable automatic decryption/encryption of .gpg files
  (setq epa-pinentry-mode 'loopback)  ;; Optional: use Emacs minibuffer for passphrase
)

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
;(load-theme 'tango-dark)

(if (eq system-type 'windows-nt)
    (cd (getenv "HOME")))

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
      org-cycle-hide-drawer-startup t
      )
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
	 :auto-preamble t
	 )
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
         :html-postamble nil
	 )
	))

(org-babel-do-load-languages
 'org-babel-load-languages
 '(
   (plantuml . t)
   (dot . t)
   (shell . t)
   (python . t)))

;;(setq org-babel-shell-names '("pwsh"))
;;(setq shell-file-name "C:/Program Files/PowerShell/7/pwsh.exe")

(setq explicit-shell-file-name shell-file-name)


(setq org-plantuml-jar-path (expand-file-name "~/plantuml.jar")
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
  
	;; Print the final list of files
	;; (message "Final file list: %s" file-list))
	

;;(prefer-coding-system 'utf-8)

(defun my/org-confirm-babel-evaluate (lang body)
  (not (or (string= lang "plantuml")
	   (string= lang "python")
	   (string= lang "dot"))))  ; don't ask for plantuml

(setq org-confirm-babel-evaluate 'my/org-confirm-babel-evaluate)


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
(load-library "~/project_config.el")
(load-library "~/keymap.el")

;;------------------------------------------------------------------------------
(setq eshell-prompt-function
      (lambda ()
        (concat
         (propertize (eshell/pwd) 'face `(:foreground "cyan"))
         (propertize " $ " 'face `(:foreground "yellow")))))
(setq eshell-highlight-prompt nil)

;;------------------------------------------------------------------------------
(use-package doom-modeline
  :ensure t
  :init
  (doom-modeline-mode 1)
  :custom
  ((doom-modeline-height 15)
   (doom-modeline-icon t)))

(use-package doom-themes
  :ensure t
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled
  (load-theme 'wombat t)

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Enable custom neotree theme (all-the-icons must be installed!)
  ; (doom-themes-neotree-config)
  ;; or for treemacs users
  (setq doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
  (doom-themes-treemacs-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

(use-package orderless
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

;;------------------------------------------------------------------------------
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(browse-url-chrome-program "C:/Program Files (x86)/Google/Chrome/Application/chrome")
 '(browse-url-firefox-program "c:/Program Files/Firefox/firefox")
 '(custom-safe-themes
   '("4594d6b9753691142f02e67b8eb0fda7d12f6cc9f1299a49b819312d6addad1d"
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
   '("c:/home/jari/org-roam/abb/abb.org"
     "c:/home/jari/org-roam/abb/abb_parameters.org"
     "c:/home/jari/org-roam/abb/abb_repositories.org"
     "c:/home/jari/org-roam/abb/abb_wiki.org"))
 '(org-export-with-broken-links 'mark)
 '(package-selected-packages
   '(ace-window avy consult copilot-chat csharp-mode dashboard
		doom-modeline doom-themes elfeed flycheck
		imenu-anywhere magit orderless org-modern org-roam
		org-roam-ui powershell projectile vertico
		which-key)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
