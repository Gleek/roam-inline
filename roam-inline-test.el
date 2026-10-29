;;; roam-inline-test.el --- Section boundary regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'roam-inline)

(defmacro roam-inline-test--with-section (text &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (let ((org-mode-hook nil)) (org-mode))
     (setq-local roam-inline-show-unlinked nil)
     (insert ,text)
     (goto-char (point-min))
     (search-forward "Last")
     (let ((node (org-roam-node-create :id "test" :title "Test")))
       (cl-letf (((symbol-function 'org-roam-node-at-point) (lambda (&rest _) node))
                 ((symbol-function 'org-roam-backlinks-get) (lambda (_) nil)))
         (roam-inline-mode 1)
         ,@body))))

(ert-deftest roam-inline-insert-heading-before-references ()
  (dolist (text '("* Last" "* Last\nBody\n" "* Last\nBody\n\n"
                  "* Parent\n** Last\nBody\n"
                  "* Last\nBody\n#+ROAM_INLINE:\n* Following\n"))
    (roam-inline-test--with-section text
      (let ((level (org-current-level)))
        (should (eq (key-binding (kbd "C-<return>"))
                    'org-insert-heading-respect-content))
        (call-interactively (key-binding (kbd "C-<return>")))
        (should (org-at-heading-p))
        (should (= (org-current-level) level))
        (should (string-empty-p (org-get-heading t t t t)))
        (should-not (get-text-property (point) 'roam-inline-managed))
        (insert "New")
        (let ((start (text-property-any (point-min) (point-max) 'roam-inline-start t)))
          (should start)
          (should (get-text-property start 'read-only))
          (should-error (delete-region start (1+ start)) :type 'text-read-only)
          (dolist (ov (overlays-in (point-min) (point-max)))
            (when (overlay-get ov 'roam-inline)
              (should (= (overlay-start ov) start)))))
        (roam-inline--prune)
        (should-not (string-match-p "Unlinked references" (buffer-string)))
        (should (string-match-p "Last\n" (buffer-string)))
        (should (string-match-p "^\\*+ New" (buffer-string)))
        (when (string-match-p "Following" text)
          (should (string-match-p "Following" (buffer-string))))))))

(ert-deftest roam-inline-refresh-repairs-separator ()
  (dolist (text '("* Last" "* Last\n" "* Last\n#+ROAM_INLINE:"
                  "* Last\n#+ROAM_INLINE:\n* Following\n"))
    (roam-inline-test--with-section text
      (let ((start (text-property-any (point-min) (point-max) 'roam-inline-start t)))
        (should (eq (char-before start) ?\n))
        (should-not (get-text-property (1- start) 'read-only))
        (delete-region (1- start) start))
      (roam-inline-refresh)
      (let ((start (text-property-any (point-min) (point-max) 'roam-inline-start t)))
        (should start)
        (should (eq (char-after start) ?*))
        (should (eq (char-before start) ?\n)))
      (let ((contents (buffer-string)))
        (roam-inline-refresh)
        (should (equal contents (buffer-string))))
      (roam-inline--prune)
      (should (equal (buffer-string)
                     (if (string-suffix-p "\n" text) text (concat text "\n")))))))

(ert-deftest roam-inline-undo-heading-keeps-section-prunable ()
  (roam-inline-test--with-section "* Last"
    (buffer-enable-undo)
    (setq buffer-undo-list nil)
    (undo-boundary)
    (org-insert-heading-respect-content)
    (insert "New")
    (undo-boundary)
    (let ((inhibit-message t)) (undo-only 1))
    (roam-inline--prune)
    (should (equal (buffer-string) "* Last\n"))))

(ert-deftest roam-inline-text-after-section-stays-editable ()
  (roam-inline-test--with-section "* Last\n#+ROAM_INLINE:\n* Following\n"
    (goto-char (next-single-property-change
                (text-property-any (point-min) (point-max) 'roam-inline-start t)
                'roam-inline-managed))
    (insert "* Added\n")
    (should-not (get-text-property (1- (point)) 'roam-inline-managed))
    (roam-inline--prune)
    (should (equal (buffer-string)
                   "* Last\n#+ROAM_INLINE:\n* Added\n* Following\n"))))

;;; roam-inline-test.el ends here
