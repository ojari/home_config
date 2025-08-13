
(defvar tempo-tags-c nil   "tempo for c language")
(defvar tempo-tags-cpp nil "tempo for c++ language")
(defvar tempo-tags-cs nil "tempo for c# language")


(require 'tempo)
(setq tempo-interactive t)


(tempo-define-template
 "c-if"
 '("if (" p ") {" >n
   "" >n
   "}" >n)
 "if"
 "if statement"
 tempo-tags-c)

(tempo-define-template
 "c-else"
 '("else {" >n
   "" p  >n
   "}" >n)
 "else"
 "else statement"
 tempo-tags-c)

(tempo-define-template
 "c-for"
 '("for (i=" p "; i<; i++) {" >n
   "" p  >n
   "}" >n)
 "for"
 "for statement"
 tempo-tags-c)


(defun insert-tw-group (group)
  (interactive "sGroup:")
  (progn
    (insert "/*") (newline)
    (insert " * ") (insert group) (newline)
    (insert " */") (newline) (newline)))

(tempo-define-template
 "tw-c"
 '("// Company Oy (C) " (format-time-string "%Y") " by Jari Ojanen" n>
   "//" n>
   "#include \"" (concat (file-name-sans-extension (file-name-nondirectory (buffer-file-name))) ".h") "\"" n>
   ;;(insert-tw-group "Include files") n>
   ;;(insert-tw-group "Local macro definitions") n>
   ;;(insert-tw-group "Local variables") n>
   ;;(insert-tw-group "Function prototypes") n>
   ;;(insert-tw-group "Functions") n>
   n>)
 "twc"
 "c template"
 tempo-tags-c)


(defun file-name-define ()
  (interactive)
  (concat "__"
	  (upcase
	   (file-name-sans-extension
	    (file-name-nondirectory (buffer-file-name))))
	  "_H__"))


(tempo-define-template
 "tw-h"
 '("// Company Oy (C) " (format-time-string "%Y") " by Jari Ojanen" n>
   "//" n>
   "#ifndef " (file-name-define) n>
   "#define " (file-name-define) n>
   n>
   (insert-tw-group "Include files") n> n>
   (insert-tw-group "Global macro definitions") n> n>
   (insert-tw-group "Global variables") n> n>
   (insert-tw-group "Functions") n>
   n>
   "#endif   // " (file-name-define) n>)
 "twh"
 "h template"
 tempo-tags-c)
