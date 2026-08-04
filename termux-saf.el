(require 'json)
(require 'map)

;; --- Configuration ---
(defcustom termux-saf-root-uri nil
  "The SAF URI root for your protected folder.
Set this using M-x set-variable or in your init file.
Example: \"content://com.android.externalstorage.documents/tree/1234-5678:Documents\""
  :group 'termux-saf
  :type 'string)

(defcustom termux-saf-temp-dir "~/saf-temp/"
  "Local directory to store temporary copies of SAF files."
  :group 'termux-saf
  :type 'directory)

(setq termux-saf-root-uri "content://com.android.externalstorage.documents/tree/0084-3000%3ABooks/document/0084-3000%3ABooks")

;; --- Helper Functions ---

(defun termux-saf--exec (command &optional args)
  "Execute a termux-saf COMMAND with ARGS and return parsed JSON.
Handles errors where the command returns non-JSON text."
  (let* ((cmd-args (append (list command) args))
         (raw-output (shell-command-to-string (mapconcat #'shell-quote-argument cmd-args " ")))
         (trimmed-output (string-trim raw-output)))
    (if (string-empty-p trimmed-output)
        nil
      (condition-case err
          (json-read-from-string trimmed-output)
        (error
         (error "termux-saf command failed (non-JSON output): %s" trimmed-output))))))

(defun termux-saf--ensure-temp ()
  "Ensure the temporary directory exists."
  (unless (file-directory-p termux-saf-temp-dir)
    (make-directory termux-saf-temp-dir t)))

;; --- API Functions ---

(defun termux-saf-list (uri)
  "List files in the SAF URI. Returns a list of alists with 'name', 'uri', and 'mime-type'."
  (if (null uri)
      (error "termux-saf-root-uri is not set"))
  (let ((result (termux-saf--exec "termux-saf-ls" (list uri))))
    ;; Handle case where result is not a list (e.g., single object or error handled above)
    (if (listp result)
        result
      (list result))))

(defun termux-saf-get-file (uri &optional filename)
  "Copy a file from SAF URI to a local temp file.
Returns the local file path.
If FILENAME is not provided, generates one based on the URI."
  (termux-saf--ensure-temp)
  (let* ((local-name (or filename (format "saf-file-%d" (random))))
         (local-path (expand-file-name local-name termux-saf-temp-dir))
         ;; termux-saf-read usually writes to stdout, so we redirect
         (cmd (format "termux-saf-read '%s' > '%s'" uri local-path)))
    (message "Copying from SAF to %s..." local-path)
    (if (zerop (shell-command cmd))
        (progn
          (message "File copied successfully.")
          local-path)
      (error "Failed to read file from SAF. Check permissions."))))

(defun termux-saf-write-file (local-path target-dir-uri &optional new-filename)
  "Write LOCAL-PATH back to the SAF TARGET-DIR-URI.
Optionally rename the file to NEW-FILENAME.
Removes the local temp copy after successful upload."
  (let* ((filename (or new-filename (file-name-nondirectory local-path)))
         ;; termux-saf-write syntax: termux-saf-write <parent_dir_uri> <filename> < input_file
         (cmd (format "cat '%s' | termux-saf-write '%s' '%s'"
                      local-path target-dir-uri filename)))
    (message "Writing %s back to SAF..." filename)
    (if (zerop (shell-command cmd))
        (progn
          (message "File written to SAF successfully.")
          (delete-file local-path) ;; Remove temp copy
          t)
      (error "Failed to write file to SAF."))))

;; --- Convenience Workflow for EXWM/Emacs ---

(defun termux-saf-open-and-edit (uri)
  "Open a file from SAF URI, edit it locally, and prompt to save back.
Intended for use with EXWM workflows."
  (interactive "sEnter SAF URI: ")
  (let* ((local-file (termux-saf-get-file uri))
         (buffer (find-file local-file)))
    (with-current-buffer buffer
      (setq-local termux-saf--original-uri uri)
      (setq-local termux-saf--target-dir (file-name-directory local-file)) ;; Logic to extract dir URI needed if different
      (add-hook 'kill-buffer-hook #'termux-saf--prompt-save-back nil t))))

(defun termux-saf--prompt-save-back ()
  "Hook function to prompt saving back to SAF when buffer is killed."
  (when (and (boundp 'termux-saf--original-uri) termux-saf--original-uri)
    (when (y-or-n-p (format "Save changes back to SAF for %s? " (buffer-file-name)))
      (let* ((uri termux-saf--original-uri)
             ;; Extract parent URI logic is complex; assuming user saves to same folder
             ;; In a real scenario, you might need to store the parent-dir-uri separately
             (parent-uri (read-string "Enter Parent Directory SAF URI: "
                                      (file-name-directory uri)))
             (filename (file-name-nondirectory (buffer-file-name))))
        (termux-saf-write-file (buffer-file-name) parent-uri filename)))))

;; --- Usage Example ---
;; 1. Set your root URI:
;;    M-x set-variable RET termux-saf-root-uri RET "content://..."
;; 2. List files:
;;    (termux-saf-list termux-saf-root-uri)
;; 3. Get a specific file (you need the file's specific URI from the list):
;;    (termux-saf-get-file "content://.../file.pdf")