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


