;(define-key input-decode-map [?\C-i] [C-i])
;(define-key input-decode-map [?\C-m] [C-m])
(define-key key-translation-map (kbd "§") (kbd "ESC"))

(global-unset-key (kbd "C-z"))
(global-unset-key (kbd "C-j"))
;(global-unset-key (kbd "<C-i>"))
;(global-unset-key (kbd "C-m"))
(global-unset-key (kbd "C-t"))
(global-unset-key (kbd "C-d"))
(global-unset-key (kbd "M-j"))
 
;(define-prefix-command 'my-mmenu)
;(global-set-key (kbd "<C-m>") 'my-mmenu)
;(define-key my-mmenu "c" 'compile);
;(define-key my-mmenu "d" 'gdb)
;(define-key my-mmenu "t" 'ido-goto-symbol)

(define-prefix-command 'my-tmenu)
(global-set-key (kbd "C-t") 'my-tmenu)
(define-key my-tmenu "t" 'transpose-chars)
(define-key my-tmenu "w" 'transpose-words)
(define-key my-tmenu "l" 'transpose-lines)
(define-key my-tmenu "p" 'transpose-paragraphs)
(define-key my-tmenu "s" 'transpose-sentences)

(define-prefix-command 'my-dmenu)
(global-set-key (kbd "C-d") 'my-dmenu)
(define-key my-dmenu "d" 'delete-char)
(define-key my-dmenu "w" 'backward-kill-word)
(define-key my-dmenu "p" 'backward-kill-paragraph)
(define-key my-dmenu "s" 'backward-kill-sentence)

(define-prefix-command 'my-jmenu)
(global-set-key (kbd "C-j") 'my-jmenu)
(define-key my-jmenu "m" 'compile)
(define-key my-jmenu "g" 'magit-status)
(define-key my-jmenu "j" 'ido-m-x)
(define-key my-jmenu "b" 'ido-switch-buffer)
(define-key my-jmenu "c" 'avy-copy-line)
(define-key my-jmenu "a" 'avy-goto-char-2)
(define-key my-jmenu "f" 'eclim-problems-correct)
(define-key my-jmenu "p" 'eclim-project-build)


;(global-set-key (kbd "<C-m>") 'newline)

(global-set-key (kbd "C-z") 'undo)
;(global-set-key (kbd "<C-i>") 'previous-line)
;(global-set-key (kbd "TAB") 'indent-region)
;(global-set-key (kbd "C-j") 'backward-char)

(global-set-key (kbd "M-i") 'previous-line)
(global-set-key (kbd "M-k") 'next-line)
(global-set-key (kbd "M-l") 'forward-char)
(global-set-key (kbd "M-j") 'backward-char)

