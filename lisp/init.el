;;; init.el --- Emacs configuration -*- lexical-binding: t -*-

;;; ── Package system ──────────────────────────────────────────────────────────

(require 'package)
(setq package-check-signature nil)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(add-to-list 'package-archives '("gnu"   . "https://elpa.gnu.org/packages/") t)
(package-initialize)

(add-to-list 'load-path (getenv "HOME"))

;;; ── Core ────────────────────────────────────────────────────────────────────

(use-package emacs
  :ensure nil
  :custom
  (inhibit-startup-message t)
  (initial-scratch-message "")
  (create-lockfiles nil)
  (make-backup-files nil)
  (use-short-answers t)
  (visible-bell 1)
  (system-time-locale "fi")
  (frame-title-format "emacs - %b")
  (tab-width 4)
  (tab-stop-list (number-sequence 4 200 4))
  (user-full-name "Jari Ojanen")
  (compilation-scroll-output t)
  (ls-lisp-dirs-first t)
  (ls-lisp-ignore-case t)
  (ls-lisp-verbosity nil)
  (ls-lisp-use-insert-directory-program nil)
  (calendar-week-start-day 1)
  (minibuffer-message-timeout 0)
  (gdb-many-windows nil)
  (explicit-shell-file-name shell-file-name)
  :config
  (require 'server)
  (unless (server-running-p) (server-start))
  (show-paren-mode t)
  (menu-bar-mode -1)
  (tool-bar-mode -1)
  (set-fringe-mode 10)
  (set-face-attribute 'default nil :font "Fira Code" :height 120)
  (if window-system
      (progn (tooltip-mode -1))
    (xterm-mouse-mode))
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
  (setq ibuffer-saved-filter-groups
        '(("default"
           ("C++"      (or (mode . c-mode) (mode . c++-mode)))
           ("org"      (or (mode . org-mode)
                           (name . "^\\*Org Src")
                           (name . "^\\*Org Agenda\\*$")))
           ("emacs"    (or (name . "^\\*scratch\\*$")
                           (name . "^\\*Messages\\*$")
                           (name . "^\\*Warnings\\*$")
                           (name . "^\\*Shell Command Output\\*$")
                           (name . "^\\*Async-native-compile-log\\*$")))
           ("ediff"    (name . "^\\*[Ee]diff.*"))
           ("vc"       (name . "^\\*vc-.*"))
           ("dired"    (mode . dired-mode))
           ("terminal" (or (mode . term-mode)
                           (mode . shell-mode)
                           (mode . eshell-mode)))
           ("help"     (or (name . "^\\*Help\\*$")
                           (name . "^\\*info\\*$"))))))
  (add-hook 'ibuffer-mode-hook
            (lambda () (ibuffer-switch-to-saved-filter-groups "default")))
  (setq ibuffer-show-empty-filter-groups nil))

(define-prefix-command 'my-jmenu)

(load-theme 'wombat t)

;;; ── Completion ──────────────────────────────────────────────────────────────

;; UI: built-in fido-vertical-mode (icomplete + ido-like keys).
(use-package icomplete
  :ensure nil
  :custom
  (icomplete-compute-delay 0)
  (icomplete-max-delay-chars 0)
  (icomplete-delay-completions-threshold 0)
  (icomplete-show-matches-on-no-input t)
  (icomplete-hide-common-prefix nil)
  (icomplete-prospects-height 10)
  (icomplete-in-buffer t)
  (icomplete-scroll t)
  :config
  ;; Candidates with no explicit sort order are sorted by length, then
  ;; alphabetically (hard-coded in `completion-all-sorted-completions').
  ;; Sort purely alphabetically instead; history items still come first.
  (advice-add 'minibuffer--sort-by-length-alpha :override
              (lambda (elems) (sort elems #'string-version-lessp))
              '((name . my/sort-alpha)))
  ;; fido forces `completion-styles' to (flex), whose score also favours
  ;; short names.  Use the global styles below instead (flex as fallback).
  (defun my/fido-use-global-styles ()
    (when (and fido-mode (local-variable-p 'completion-styles))
      (kill-local-variable 'completion-styles)))
  (add-hook 'minibuffer-setup-hook #'my/fido-use-global-styles 90)
  (fido-vertical-mode 1))

(use-package minibuffer
  :ensure nil
  :custom
  (completion-styles '(substring partial-completion flex))
  (completion-category-overrides '((file (styles partial-completion substring))))
  (completion-ignore-case t)
  (completions-detailed t)
  (completions-format 'one-column)
  (completions-max-height 20)
  (completions-sort 'alphabetical)
  (enable-recursive-minibuffers t)
  (read-buffer-completion-ignore-case t)
  (read-file-name-completion-ignore-case t))

(use-package savehist
  :ensure nil
  :config
  (savehist-mode 1))

(use-package consult
  :ensure t
  :defer t)

;;; ── Org ─────────────────────────────────────────────────────────────────────

(use-package org
  :ensure nil
  :defer t
  :hook
  (org-mode . visual-line-mode)
  :custom
  (org-startup-with-inline-images t)
  (org-startup-with-latex-preview nil)
  (org-cycle-hide-drawer-startup t)
  (org-export-coding-system 'utf-8)
  (org-plantuml-jar-path (expand-file-name "/usr/plantuml.jar"))
  (org-mobile-directory "/tmp/org-mobile")
  (org-time-stamp-custom-formats '("<%m/%d/%y %a>" . "<%d/%m %a %H:%M>"))
  (org-link-frame-setup '((file . find-file)))
  (org-agenda-start-with-clockreport-mode t)
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
             (string= lang "dot"))))
  (setq org-confirm-babel-evaluate 'my/org-confirm-babel-evaluate)
  (setq org-publish-project-alist
        '(("github"
           :base-directory "~/ojari.github.io/"
           :base-extension "org"
           :publishing-directory "~/ojari.github.io/"
           :recursive t
           :publishing-function org-html-publish-to-html
           :headline-levels 4
           :auto-preamble t
		   :style "<link rel=\"stylesheet\"
                 href=\"worg.css\"
                 type=\"text/css\"/>" )

          ("org-roam"
           :base-directory "~/org-roam/"
           :base-extension "org"
           :publishing-directory "~/tmp/"
           :recursive t
           :publishing-function org-html-publish-to-html
           :headline-levels 4
           :section-numbers nil
           :with-author nil
           :with-toc nil
           :time-stamp-file nil
           :html-head "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\" />"
           :html-preamble nil
           :html-postamble nil))))

(use-package org-roam
  :ensure t
  :defer t
  :custom
  (org-roam-completion-system 'default)
  (org-roam-completion-everywhere t)
  (org-roam-directory "~/org-roam")
  (org-roam-buffer-window-parameters '((no-delete-other-windows . t)))
  :config
  (define-key org-mode-map (kbd "C-j") 'my-jmenu))

;;; ── Programming ─────────────────────────────────────────────────────────────

(use-package cc-mode
  :ensure nil
  :defer t
  :hook
  ((c-mode   . (lambda ()
                 (c-set-style "stroustrup")
                 (setq indent-tabs-mode nil)
                 (setq c-basic-offset 4)))
   (c++-mode . (lambda ()
                 (c-set-style "stroustrup")
                 (setq indent-tabs-mode nil)
                 (setq c-basic-offset 4)))))

(use-package project
  :ensure nil
  :defer t)

;;; ── Tools ───────────────────────────────────────────────────────────────────

(use-package magit
  :ensure t
  :defer t)

(use-package rg
  :ensure t
  :defer t
  :custom
  (rg-root-directory "~/"))

(use-package which-key
  :ensure t
  :config
  (which-key-mode))

(use-package dired
  :ensure nil
  :defer t
  :bind
  (:map dired-mode-map
        ("e" . my/dired-ediff-files)
        ("j" . dired-up-directory)
        ("l" . dired-find-file)
        ("k" . dired-next-line)
        ("i" . dired-previous-line)
        ("q" . quit-window))
  :config
  (defun my/dired-ediff-files ()
    (interactive)
    (let ((files (dired-get-marked-files))
          (wnd (current-window-configuration)))
      (if (= (length files) 2)
          (progn
            (message (car files))
            (ediff-files (car files) (cadr files))
            (add-hook 'ediff-after-quit-hook-internal
                      (lambda ()
                        (setq ediff-after-quit-hook-internal nil)
                        (set-window-configuration wnd))))
        (error "no more than 2 files should be marked")))))

(use-package vterm
  :ensure t
  :defer t)

(defun my/send-to-vterm (beg end)
  "Send the region, or the current line, to vterm.
Line breaks inside the text go as Shift+Return; one Return goes at the end."
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (require 'vterm)
  (let* ((text (string-trim-right
                (buffer-substring-no-properties beg end) "\n+"))
         (lines (split-string text "\n"))
         (buf (or (get-buffer "*vterm*")
                  (read-buffer "Send to vterm buffer: " nil t
                               (lambda (b)
                                 (with-current-buffer (if (consp b) (car b) b)
                                   (eq major-mode 'vterm-mode)))))))
    (with-current-buffer buf
      (while lines
        (vterm-send-string (pop lines))
        (when lines
          (vterm-send-key "<return>" t)))   ; Shift+Return
      (vterm-send-return))                  ; final Return
    (deactivate-mark)
    (display-buffer buf)))

(global-set-key (kbd "C-c v s") #'my/send-to-vterm)

(use-package aidermacs
  :bind (("C-c a" . aidermacs-transient-menu))
  :custom
  (aidermacs-backend 'vterm)
  (aidermacs-default-model "Qwen3.5-9B-IQ4_XS")
  (aidermacs-extra-args
   '("--openai-api-base" "http://127.0.0.1:8080/v1"
     "--openai-api-key" "local")))

;;; ── Extras ──────────────────────────────────────────────────────────────────

;; ISO week numbers in calendar
(copy-face font-lock-constant-face 'calendar-iso-week-face)
(set-face-attribute 'calendar-iso-week-face nil :height 0.6)
(setq calendar-intermonth-text
      '(propertize
        (format "%2d"
                (car (calendar-iso-from-absolute
                      (calendar-absolute-from-gregorian (list month day year)))))
        'font-lock-face 'calendar-iso-week-face))

(defun my/region-transfer ()
  "Copy active region into the next window."
  (interactive)
  (if (region-active-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
        (other-window 1)
        (insert text)
        (insert "\n")
        (other-window 1))
    (message "No region active!")))

(defun magit-ignore-whitespace ()
  (interactive)
  (add-to-list 'magit-diff-options "-w")
  (magit-refresh))

;;; ── Load external config ────────────────────────────────────────────────────

(load-library "~/home_config/lisp/project_config.el")
(load-library "~/home_config/lisp/keymap.el")

;;; ── Custom (managed by Emacs — do not edit manually) ────────────────────────

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("f654d73d7a0761cc4f7d99fffe4b16fce1b2d95844f37bc786e455cec744ac75"
	 "e8bd9bbf6506afca133125b0be48b1f033b1c8647c628652ab7a2fe065c10ef0"
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
 '(magit-diff-arguments '("--stat" "--no-ext-diff" "-w"))
 '(magit-fetch-arguments nil)
 '(org-export-with-broken-links 'mark)
 '(package-selected-packages
   '(aidermacs consult eat inheritenv magit markdown-mode org-roam
			   projectile rg treemacs vterm))
 '(safe-local-variable-values '((gud-gdb-command-name . "gdb -i=mi build_debug/pctests")))
 '(speedbar-supported-extension-expressions
   '(".cmake" "CMakeLists\\.txt" ".md" "\\.md$"
	 ".[ch]\\(\\+\\+\\|pp\\|c\\|h\\|xx\\)?" ".el" ".emacs" ".java"
	 ".js" ".p[lm]" ".tcl" ".m" ".scm" ".pm" ".py" ".lua" ".s?html"
	 ".ma?k" "[Mm]akefile\\(\\.in\\)?")))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
