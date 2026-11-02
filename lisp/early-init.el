;;; early-init.el --- Pre-GUI startup settings -*- lexical-binding: t -*-

;; Packages are initialized explicitly in init.el.
(setq package-enable-at-startup nil)

;; Fewer garbage collections during startup, then back to a sane value.
(setq gc-cons-threshold (* 64 1024 1024))
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

;; Disable bars before the first frame is drawn (no flicker).
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(setq menu-bar-mode nil
      tool-bar-mode nil)
