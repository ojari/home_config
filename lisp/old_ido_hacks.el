;;------------------------------------------------------------------------------
(load-library "bookmark")
(defun ido-bookmarks ()
  (interactive)
  (let ((bmark (ido-completing-read "Bookmark:" (bookmark-all-names) nil t)))
    (bookmark-jump bmark)))

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

(defun ido-open-org-roam-node ()
  (interactive)
  (find-file
   (org-roam-get-file-by-title
    (ido-completing-read
     "Node:"
     (mapcar #'org-roam-node-title (org-roam-node-list))
     nil
     t))))


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

;; (defun mbed-flash ()
;;   (interactive)
;;   (copy-file "BUILD/blinky.bin" "D:/"))

;; (defun arm-gdb ()
;;   (interactive)
;;   (setq gdb-many-windows nil)
;;   (gdb "/mnt/bin/gcc-arm/bin/arm-none-eabi-gdb -i=mi bin/meas.elf"))


;(ido-mode t)
;(ido-everywhere t)
;;(ido-vertical-mode t)
;;(setq ido-enable-flex-matching t
;;      ido-everywhere t)

(setq
  nnmail-spool-file "Z:/backup/.../thunderbird/.../Mail/LocalFolders/InBox"
  gnus-select-method '(nnml ""))

(setq projectile-globally-ignored-directories
      (list ".idea" ".vscode" ".git" ".hg" ".fslckout"
	    ".cache" ".clangd" ".sl" ".jj" "*Tests" "*virtualizations"))

