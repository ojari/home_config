(eval-after-load 'autoinsert
  '(progn
     (define-auto-insert '("\\.c\\'" . "C skeleton")
       '(
	 "Short description: "
	 "/*----------------------------------------------------" \n
	 "* Name:         " (file-name-nondirectory (buffer-file-name)) \n
	 "* Purpose:      " str \n
	 "* Created:      " (format-time-string "%d.%m.%Y") " by Jari Ojanen" \n
	 "*----------------------------------------------------" \n
	 "*/" \n \n
	 "#include <stdio.h>" \n
	 "#include \""
	 (file-name-sans-extension
          (file-name-nondirectory (buffer-file-name)))
	 ".h\"" \n \n
	 "int main()" \n
	 "{" > \n
	 > _ \n
	 "}" > \n
	 "/* The end of file */" \n))
     (define-auto-insert '("\\.h\\'" . "C/C++ Header skeleton")
       (let ((guard (upcase (concat (file-name-sans-extension (file-name-nondirectory (buffer-file-name))) "_H_"))))
         `(
	   "Include guard"
           "#ifndef " ,guard \n
           "#define " ,guard \n \n
           _ \n \n
           "#endif /* " ,guard " */" \n
           )))))


(defun my/compile (target)
  "Run the my compile script with a selected target."
  (interactive
   (list (completing-read "Choose target: " '("UBuild" "UConfig" "VBuild" "test" "OReport" "build" "config" "udemo" "tags" "generator" "UUpdate"))))
  (let ((default-directory "/Users/ett12814/refactored/"))
    (compile (format "pwsh jt/make.ps1 %s" target))))

(set-register ?e "senior sw engineer")
(set-register ?i ":CATEGORY: AI\n")
(set-register ?l ":CATEGORY: Learn\n")
(set-register ?w ":CATEGORY: SW\n")
(set-register ?s ":CATEGORY: Sport\n")
(set-register ?a "#+filetags:  :abb:\n")
(set-register ?p "#+begin_src python\n\n#+end_src\n")

(setq magit-repository-directories
      '(
	("/Users/ett12814/org-roam" . 1)))

(setq org-roam-capture-templates
      '(
	("u" "punta" plain (file "~/org-roam/templates/punta.org")
	 :target (file+head "punta/${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("s" "study" plain (file "~/org-roam/templates/study.org")
	 :target (file+head "study/${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("i" "ai" plain (file "~/org-roam/templates/ai.org")
	 :target (file+head "ai/${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("p" "programming" plain (file "~/org-roam/templates/programming.org")
	 :target (file+head "programming/${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	("h" "hobby" plain (file "~/org-roam/templates/hobby.org")
	 :target (file+head "hobby/${slug}.org"
			    "#+title: ${title}\n") :unnarrowed t)
	)
      )

(setq
 elfeed-feeds '(
		"https://feeds.redcircle.com/42bb5015-064c-489d-b9e9-4d8f0af4aed0?_gl=1*426cnu*_gcl_au*NzgyOTk0Njg2LjE3NTUxNjcwNDc.*_ga*ODIwNjA4MzcuMTc1NTE2NzA0Nw..*_ga_KVZ47LYJWW*czE3NTUxNjcwNDYkbzEkZzAkdDE3NTUxNjcwNDYkajYwJGwwJGgw" ;; Modern aikidoist
		))
(setq
  nnmail-spool-file "Z:/backup/.../thunderbird/.../Mail/LocalFolders/InBox"
  gnus-select-method '(nnml ""))

(setq copilot-chat-org-prompt "The user works in an IDE called Emacs which has an org major mode for keeping notes, authoring documents, computational notebooks, literate programming, maintaining to-do lists, planning projects, and more — in a fast and effective plain text system.

Use only Emacs org-mode formatting in your answers.
When using heading to structure your answer, please start at level 2 (i.e with 2 stars or more)
Make sure to include the programming language name at the start of the org-mode code blocks.
This is an example of python code block in emacs org-mode syntax:
#+BEGIN_SRC python
def hello_world():
	print('Hello, World!')
#+END_SRC
Avoid wrapping the whole response in the block code.
Limit the line length to 90 characters.
Target reponse to senior sw engineer.

Don't forget the most important rule when you are formatting your response: use emacs org-mode syntax only.")


(defun my/clock-to-clk (start end)
  "Convert :CLOCK: lines to #+CLK: lines in region or buffer.
  Example: :CLOCK: [2025-10-08 Wed 10:00]--[2025-10-08 Wed 12:00] =>  2:00
  becomes: #+CLK: [2025-10-08 Wed 2:00]"
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (point-min) (point-max))))
  (save-excursion
    (goto-char start)
    (while (re-search-forward
            "CLOCK: \\[\\([0-9-]+ [A-Za-z]+\\) [0-9:]+\\]--\\[[^]]+\\] => *\\([0-9]+:[0-9]+\\)"
            end t)
      (replace-match "#+CLK: [\\1 \\2]"))))

(defun my/org-generate-clock-entry (duration)
  "Generate a CLOCK line using today's date and DURATION (HH:MM)."
  (interactive "sDuration (HH:MM): ")
  (let* ((date (format-time-string "%Y-%m-%d"))
         (duration-parts (split-string duration ":"))
         (dur-hour (string-to-number (car duration-parts)))
         (dur-min (string-to-number (cadr duration-parts)))
         (weekday (format-time-string "%a"))
         (clock-line (format "#+CLK: [%s %s %02d:%02d]" date weekday dur-hour dur-min)))
    (insert clock-line)))

(defun my/org-refresh-clocktables ()
  "Refresh clocktables by opening all agenda files and updating dynamic blocks."
  (interactive)
  ;; Load all agenda files
  (dolist (file org-agenda-files)
    (unless (get-file-buffer file)
      (find-file-noselect file)))
  ;; Update dynamic blocks in current buffer
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^#\\+BEGIN: clocktable" nil t)
      (org-update-dblock))))

(defvar my-filelist-path "/home/abb/PCT380/org.projectile"
  "Full path to the text file containing the list of files.")

(defvar my-base-dir "/home/abb/PCT380"
  "Base directory to prepend to relative file paths.")

(defun my/open-file-from-list ()
  "Open a file from a fixed list with completion.
Filenames in `my-filelist-path` are considered relative to `my-base-dir`."
  (interactive)
  (let* ((candidates (with-temp-buffer
                       (insert-file-contents my-filelist-path)
                       (split-string (buffer-string) "\n" t))) ;; remove empty lines
         (choice (completing-read "Open file: " candidates nil t))
         (fullpath (expand-file-name choice my-base-dir)))
    (when (and choice (not (string-empty-p choice)))
      (find-file fullpath))))

(defun my/grep-in-filelist (query)
  "Search QUERY in files listed in `my-filelist-path` using Emacs rgrep."
  (interactive
   (let ((default (thing-at-point 'symbol t)))
     (list (read-string (if default
                             (format "Search for (default %s): " default)
                           "Search for: ")
                        nil nil default))))
  (let* ((files (with-temp-buffer
                  (insert-file-contents my-filelist-path)
                  (split-string (buffer-string) "\n" t)))
         (fullpaths (mapcar (lambda (f) (expand-file-name f my-base-dir))
                            files)))
    ;; Build the file pattern string for rgrep
    ;; We'll use files as multiple patterns
    (let ((grep-files (mapconcat #'identity fullpaths " ")))
      ;; Use compilation-start to run grep command
      (compilation-start
       (concat "grep -nH -e " (shell-quote-argument query) " " grep-files)
       'grep-mode))))

(defun my/md-link-to-org-link (start end)
  "Convert markdown links [text](url) to org-mode links [[url][text]] in region or buffer."
  (interactive
    (if (use-region-p)
        (list (region-beginning) (region-end))
      (list (point-min) (point-max))))
  (save-excursion
    (goto-char start)
    (while (re-search-forward "\\[\\([^]]+\\)\\](\\([^)]*\\))" end t)
      (replace-match "[[\\2][\\1]]"))))


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
