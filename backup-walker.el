;;; backup-walker.el --- quickly traverse all backups of a file

;; this file is not part of Emacs

;; Copyright (C) 2011 Le Wang
;; Author: Le Wang
;; Maintainer: Le Wang
;; Description: quickly traverse all backups of a file
;; Author: Le Wang
;; Maintainer: Le Wang

;; Created: Wed Sep  7 19:38:05 2011 (+0800)
;; Version: 0.1
;; Last-Updated: Fri Sep  9 14:35:40 2011 (+0800)
;;           By: Le Wang
;;     Update #: 66
;; URL: https://github.com/lewang/backup-walker
;; Keywords: backup
;; Compatibility: Emacs 23+

;;; Installation:

;;
;; add to ~/.emacs.el
;;
;;  (require 'backup-walker)
;;
;;   M-x backup-walker-start
;;
;; Of course, you should autoload, and bind the entry function to some key
;; sequence.  But the above gets you going.

;;; Commentary:

;; I never delete backups.  They are versioned in their own directory, happy
;; and safe.  My fingers skip to C-x C-s whenever I pause to think about
;; anything.  Even when I'm working with VCS, I save far more often than I
;; commit.
;;
;; This package helps me traverse those backups if I'm looking for something.
;;
;; The typical workflow is:
;;
;;   1) I'm in a buffer and realize I need to check some backups.
;;
;;        M-x backup-walker-start
;;
;;   2) I press <p> to go backwards in history until I see something
;;      interesting.  Then I press <enter> to bring it up.  OOPs this isn't
;;      it, I go back to the backup-walker window and find the right file.
;;
;;   3) I get what I need from the backup, go back to backup-walker, and press
;;      <q> and kill all open backups.
;;
;;   4) the end.
;;
;; Additionally, note that all the diff-mode facilities are available in the
;; `backup-walker' buffer.
;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Code:

(eval-when-compile (require 'cl))

(provide 'backup-walker)

(require 'diff)

(or (fboundp 'diff-no-select)
    (defun diff-no-select (old new &optional switches no-async)
      (save-window-excursion (diff old new switches no-async))
      (get-buffer-create "*Diff*")))


(defvar backup-walker-ro-map (make-sparse-keymap))
(define-key backup-walker-ro-map [(n)] 'backup-walker-next)
(define-key backup-walker-ro-map [(p)] 'backup-walker-previous)
(define-key backup-walker-ro-map [(q)] 'backup-walker-quit)
(define-key backup-walker-ro-map [(return)] 'backup-walker-show-file-in-other-window)

(define-derived-mode backup-walker-mode diff-mode "{Diff backup walker}"
  "major mode for traversing versioned backups.  Use
  `backup-walker-start' as entry point."
  (run-hooks 'view-mode-hook)           ; diff-mode sets up this hook to
                                        ; remove its read-only overrides.
  (add-to-list 'minor-mode-overriding-map-alist `(buffer-read-only . ,backup-walker-ro-map))
  (backup-walker-refresh))

(defvar backup-walker-data-alist nil
  "")
(make-variable-buffer-local 'backup-walker-data)

(defsubst backup-walker-get-version (fn &optional start)
  "return version number given backup"
  (if start
      (string-to-int
       (substring fn
                  (string-match "[[:digit:]]+" fn start)
                  (match-end 0)))
    (backup-walker-get-version fn (length (file-name-sans-versions fn)))))

(defun backup-walker-get-sorted-backups (filename)
  "Return version sorted list of backups of the form:

  (prefix (list of suffixes))"
  ;; `make-backup-file-name' will get us the right directory for
  ;; ordinary or numeric backups.  It might create a directory for
  ;; backups as a side-effect, according to `backup-directory-alist'.
  (let* ((filename (file-name-sans-versions
                    (make-backup-file-name (expand-file-name filename))))
         (file (file-name-nondirectory filename))
         (dir  (file-name-directory    filename))
         (comp (file-name-all-completions file dir))
         (prefix-len (length file)))
    (cons filename (mapcar
                    (lambda (f)
                      (substring (cdr f) prefix-len))
                    (sort (mapcar (lambda (f)
                                    (cons (backup-walker-get-version f prefix-len)
                                          f))
                                  comp)
                          (lambda (f1 f2)
                            (not (< (car f1) (car f2)))))))))


(defun backup-walker-refresh ()
  (let* ((index (cdr (assq :index backup-walker-data-alist)))
         (suffixes (cdr (assq :backup-suffix-list backup-walker-data-alist)))
         (prefix (cdr (assq :backup-prefix backup-walker-data-alist)))
         (right-file (concat prefix (nth index suffixes)))
         (right-version (format "%i" (backup-walker-get-version right-file)))
         diff-buff left-file left-version)
    (if (eq index 0)
        (setq left-file (cdr (assq :original-file backup-walker-data-alist))
              left-version "orig")
      (setq left-file (concat prefix (nth (1- index) suffixes))
            left-version (format "%i" (backup-walker-get-version left-file))))
    (setq diff-buf (diff-no-select left-file right-file nil 'noasync))
    (setq buffer-read-only nil)
    (delete-region (point-min) (point-max))
    (insert-buffer diff-buf)
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)
    (force-mode-line-update)
    (setq header-line-format
          (concat (format "{{ ~%s~ → ~%s~ }} "
                          (propertize left-version 'face 'font-lock-variable-name-face)
                          (propertize right-version 'face 'font-lock-variable-name-face))
                  (if (eq index 0)
                      ""
                    (concat (propertize "<n>" 'face 'italic)
                            " ~"
                            (propertize (int-to-string (backup-walker-get-version (nth (1- index) suffixes)))
                                        'face 'font-lock-keyword-face)
                            "~ "))
                  (if (nth (1+ index) suffixes)
                      (concat (propertize "<p>" 'face 'italic)
                              " ~"
                              (propertize (int-to-string
                                           (backup-walker-get-version (nth (1+ index) suffixes)))
                                          'face 'font-lock-keyword-face)
                              "~ ")
                    "")
                  (propertize "<return>" 'face 'italic)
                  " open ~"
                  (propertize (propertize (int-to-string (backup-walker-get-version right-file))
                                          'face 'font-lock-keyword-face))
                  "~"))
    (kill-buffer diff-buf)))

;;;###autoload
(defun backup-walker-start (original-file)
  "start walking with the latest backup

with universal arg, ask for a file-name."
  (interactive (list (if (and current-prefix-arg (listp current-prefix-arg))
                         (read-file-name
                          "Original file: "
                          nil
                          buffer-file-name
                          t
                          (file-name-nondirectory buffer-file-name))
                       (or buffer-file-name
                           (error "buffer has no file name")))))
  (unless (and version-control
               (not (eq version-control 'never)))
    (error "version-control must be enabled for backup-walker to function."))
  (let ((backups (backup-walker-get-sorted-backups original-file))
        alist
        buf)
    (if (null (cdr backups))
        (error "no backups found.")
      (push `(:backup-prefix . ,(car backups)) alist)
      (push `(:backup-suffix-list . ,(cdr backups)) alist)
      (push `(:original-file . ,original-file) alist)
      (push `(:index . 0) alist)
      (setq buf (pop-to-buffer (get-buffer-create (format "*Walking: %s*" (buffer-name)))))
      (with-current-buffer buf
        (setq backup-walker-data-alist alist)
        (buffer-disable-undo)
        (backup-walker-mode)))))

(defun backup-walker-next (arg)
  "move to a more recent backup
with ARG, move ARG times"
  (interactive "p")
  (cond ((< arg 0)
         (backup-walker-previous (- arg)))
        ((> arg 0)
         (let* ((index-cons (assq :index backup-walker-data-alist))
                (index (cdr index-cons))
                (new-index (- index arg)))
           (if (< new-index 0)
               (error (format "not enough newer backups, max is %i" index))
             (setcdr index-cons new-index)
             (backup-walker-refresh))))))

(defun backup-walker-previous (arg)
  "move to a less recent backup
with ARG move ARG times"
  (interactive "p")
  (cond ((< arg 0)
         (backup-walker-next (- arg)))
        ((> arg 0)
         (let* ((index-cons (assq :index backup-walker-data-alist))
                (index (cdr index-cons))
                (suffixes (cdr (assq :backup-suffix-list backup-walker-data-alist)))
                (max-movement (- (1- (length suffixes)) index)))
           (if (> arg max-movement)
               (error (format "not enough older backups, max is %i" max-movement))
             (setcdr index-cons (+ index arg))
             (backup-walker-refresh))))))

(defun backup-walker-show-file-in-other-window ()
  "open the current backup in another window.

Only call this function interactively."
  (interactive)
  (let* ((index (cdr (assq :index backup-walker-data-alist)))
         (suffixes (cdr (assq :backup-suffix-list backup-walker-data-alist)))
         (prefix (cdr (assq :backup-prefix backup-walker-data-alist)))
         (file-name (concat prefix (nth index suffixes)))
         (buf (find-file-noselect file-name)))
    (display-buffer-other-window buf)
    (setq other-window-scroll-buffer buf)))

(defun backup-walker-quit ()
  "quit backup-walker session.

Offer to kill all associated backup buffers."
  (interactive)
  (let* ((prefix (cdr (assq :backup-prefix backup-walker-data-alist)))
         (prefix-len (length prefix))
         (walking-buf (current-buffer))
         backup-bufs)
    (mapc (lambda (buf)
            (let ((file-name (buffer-file-name buf)))
              (when (and file-name
                         (>= (length file-name) prefix-len)
                         (string= prefix (substring file-name 0 prefix-len)))
                (push buf backup-bufs))))
          (buffer-list))
    (when (y-or-n-p (concat (propertize (int-to-string (length backup-bufs))
                                      'face 'highlight)
                          " backup buffers found, kill them?"))
      (mapc (lambda (buf)
              (kill-buffer buf))
            backup-bufs))
    (quit-window)
    (kill-buffer walking-buf)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; backup-walker.el ends here
