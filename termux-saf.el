(require 'json)
(require 'map)
(require 'seq)
(require 'f)
(require 'openwith)

;; --- 1. Variable Declarations (Fixes void-variable errors) ---

(defcustom termux-saf-cache-dir "~/.emacs.d/saf-cache/"
  "Local directory for temporary file copies."
  :group 'termux-saf
  :type 'directory)


(defcustom termux-saf-temp-dir "~/.emacs.d/saf-temp/"
  "Local directory for temporary file copies."
  :group 'termux-saf
  :type 'directory)

;; Declare state variables to avoid void-variable errors
(defvar termux-saf--current-uri nil
  "Tracks the current SAF URI being browsed.")
(defvar termux-saf--file-cache nil
  "Cache of file data for the current buffer to avoid re-parsing.")

;; --- 2. Robust Helper Functions ---

(defun termux-saf--exec-json (command &rest args)
  "Execute termux-saf COMMAND and return parsed JSON list.
Handles empty output and non-JSON error strings gracefully."
  (let* ((cmd-str (mapconcat #'shell-quote-argument (cons command args) " "))
         (raw (shell-command-to-string cmd-str))
         (trim (string-trim raw)))
    (cond
     ((string-empty-p trim) nil)
     ((string-prefix-p "{" trim)
      ;; If it returns a single object, wrap it in a list
      (condition-case err
          (list (json-read-from-string trim))
        (error (error "termux-saf JSON parse error: %s" raw))))
     ((string-prefix-p "[" trim)
      ;; Standard list
      (condition-case err
          (json-read-from-string trim)
        (error (error "termux-saf JSON parse error: %s" raw))))
     (t (error "termux-saf command failed: %s" trim)))))

(defun termux-saf--ensure-temp ()
  "Create temp directory if missing."
  (unless (file-directory-p termux-saf-temp-dir)
    (make-directory termux-saf-temp-dir t)))

(defun termux-saf--ensure-cache ()
  "Create cache directory if missing."
  (unless (file-directory-p termux-saf-cache-dir)
    (make-directory termux-saf-cache-dir t)))

(defun termux-saf--write-cache (data cache-file-path)
  (termux-saf--ensure-cache)
  (f-write-text (json-encode data) 'utf-8 cache-file-path))

;; --- 3. Core API Functions ---

(defun termux-saf-list (uri)
  "Lazy list files in SAF URI. Returns list of alists with 'name', 'uri', 'type', 'length', 'last_modified'."
  (unless uri (error "SAF URI is nil"))
  (let* ((cache-name (concat (base64-encode-string uri) ".json"))
          (cache-file-path (expand-file-name cache-name termux-saf-cache-dir))
          (raw (if (file-exists-p cache-file-path) (json-read-file cache-file-path) (termux-saf--exec-json "termux-saf-ls" uri)))
          ;; Ensure we return a list of records, filtering out any non-file metadata if present.
          (data (seq-filter (lambda (x) (and (listp x) (alist-get 'name x))) raw)))
    (unless (file-exists-p cache-file-path)
      (termux-saf--write-cache data cache-file-path))
    data))

(defun termux-saf-get-file (uri filename)
  "Copy file from SAF URI to temp dir using FILENAME.
Returns the full local path."
  (termux-saf--ensure-temp)
  (let* ((safe-filename (replace-regexp-in-string "[^a-zA-Z0-9._-]" "_" filename))
         (local-path (expand-file-name safe-filename termux-saf-temp-dir))
         (cmd (format "termux-saf-read '%s' > '%s'" uri local-path)))
    (message "Downloading %s..." filename)
    (if (zerop (shell-command cmd))
        (progn
          (message "Downloaded to %s" local-path)
          local-path)
      (error "Failed to download file from SAF"))))

(defun termux-saf-open-file (uri filename mime-type)
  "Download URI to temp, then use 'termux-open' to trigger Android 'Open With'."
  (let ((local-path (termux-saf-get-file uri filename))
         (openwith-mode t))
    (find-file local-path)))

;; --- 4. The Browse View (Interactive Buffer) ---

(defvar termux-saf-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'termux-saf-open-line)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'termux-saf-browse-refresh)
    (define-key map (kbd "q") 'quit-window)
    map)
  "Keymap for `termux-saf-mode`.")

(define-derived-mode termux-saf-mode special-mode "Termux-SAF"
  "Major mode for browsing Termux SAF directories."
  (setq-local revert-buffer-function #'termux-saf-browse-refresh)
  (setq-local termux-saf--current-uri nil))

(defun termux-saf-cache-clear ()
  "Delete all cached content, by deleting and recreating cache folder."
  (interactive)
  (delete-directory termux-saf-cache-dir t)
  (mkdir termux-saf-cache-dir t))

(defun termux-saf-browse (uri)
  "Create a clickable buffer listing files in SAF URI."
  (interactive "sEnter SAF URI: ")
  (let ((buffer-name (format "*SAF: %s*" (if (stringp uri) (substring uri (max 0 (- (length uri) 20))) "Root"))))
    (with-current-buffer (get-buffer-create buffer-name)
      (termux-saf-mode)
      (setq-local termux-saf--current-uri uri)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Termux SAF Browser\n")
        (insert (format "Content: %s\n\n" uri))
        (insert "--------------------------------------------------\n")

        (let ((files (termux-saf-list uri))
               (index 0))
          (if (null files)
              (insert "(Directory empty or error reading)\n")
            (dolist (file files)
              (let* ((name (alist-get 'name file))
                     (mime (or (alist-get 'type file) "application/octet-stream"))
                     (file-uri (alist-get 'uri file)))
                (setq index (1+ index))
                ;; Insert as a clickable text property
                (let ((start (point)))
                  (insert (format "%s.\t%s\n" index name))
                  (let ((end (point)))
                    (add-text-properties
                     start end
                     `(mouse-face highlight
                       face link
                       pointer hand
                       termux-saf-uri ,file-uri
                       termux-saf-name ,name)))))))))
      (goto-char (point-min))
      (forward-line 4) ;; Skip header
      (display-buffer (current-buffer)))))

(defun termux-saf-browse-refresh (&optional ignore-auto noconfirm)
  "Refresh the current SAF buffer."
  (interactive)
  (let ((uri termux-saf--current-uri))
    (if uri
        (termux-saf-browse uri)
      (message "No URI to refresh"))))

(defun termux-saf-open-line ()
  "Open the file on the current line using Android 'Open With'."
  (interactive)
  (let* ((props (text-properties-at (point)))
         (uri (plist-get props 'termux-saf-uri))
         (name (plist-get props 'termux-saf-name))
         (mime (plist-get props 'termux-saf-mime)))
    (if uri
        (termux-saf-open-file uri name mime)
      (message "No file on this line"))))