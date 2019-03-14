
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


