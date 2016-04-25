
(setq inhibit-startup-screen t
      visible-bell 1)

(global-set-key [f11] 'kill-this-buffer)
(global-set-key [f12] 'magit-status)

(tool-bar-mode -1)
(show-paren-mode 1)

(fset 'yes-or-no-p 'y-or-n-p)

(require 'package)
;(add-to-list 'package-archives
;             '("melpa" . "http://melpa.org/packages/") t)
(add-to-list 'package-archives
             '("melpa-stable" . "http://stable.melpa.org/packages/") t)

(package-initialize)

(add-hook 'c-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))

(add-hook 'c++-mode-hook
          '(lambda ()
             (c-set-style "stroustrup")))



(load-theme 'zenburn t)
;(load-theme 'tango-dark)

(cd "c:/home")

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   (quote
    ("8aebf25556399b58091e533e455dd50a6a9cba958cc4ebb0aab175863c25b9a4" "afbb40954f67924d3153f27b6d3399df221b2050f2a72eb2cfa8d29ca783c5a8" default))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
