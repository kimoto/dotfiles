1;2c:;; .emacs $Id$
;; このファイルは設定情報のsandbox的に利用する

;; environment
(set-language-environment 'japanese)
(setq default-buffer-file-coding-system 'utf-8)
(set-buffer-file-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-clipboard-coding-system 'utf-8)
(prefer-coding-system 'utf-8)
(setq slime-net-coding-system 'utf-8-unix)

;; user information
; changelog
(setq user-full-name "KIMOTO Takumi")
(setq user-mail-address "peerler@gmail.com")

;; utility
; ディレクトリ内で正規表現にマッチするファイルをloadします
(defun load-regexp-match-files-in-directory (directory-path regexp)
  (mapcar
   #'(lambda (file-path)
       (if (string-match regexp file-path)
           (load-file (concat directory-path file-path))))
   (directory-files directory-path)))

;; 指定されたパスをload-pathに追加する
(defun add-load-path (&rest path-list)
  (dolist (path path-list)
    (push path load-path)))

;; load
; load ~/.emacs.d/conf/init.*el
(add-load-path "~/.emacs.d/elisp/")
(load-regexp-match-files-in-directory "~/.emacs.d/conf/" "init.*el$")
