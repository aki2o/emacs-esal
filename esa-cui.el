(require 'log4e)
(require 'yaxception)


(log4e:deflogger "esa-cui" "%t [%l] %m" "%H:%M:%S" '((fatal . "fatal")
                                                     (error . "error")
                                                     (warn  . "warn")
                                                     (info  . "info")
                                                     (debug . "debug")
                                                     (trace . "trace")))
(esa-cui--log-set-level 'trace)


(defgroup esa-cui nil
  ""
  :group 'convenience
  :prefix "esa-cui:")

(defvar esa-cui::process-hash (make-hash-table :test 'equal))
(defvar esa-cui::access-token-hash (make-hash-table :test 'equal))
(defvar esa-cui::current-team nil)
(defvar esa-cui::response "")

(defsubst esa-cui::response-finished-p ()
  (string-match "\n?>>>\\s-\\'" esa-cui::response))


(defun esa-cui::get-process ()
  (let ((proc (gethash esa-cui::current-team esa-cui::process-hash)))
    (or (and (processp proc)
             (eq (process-status proc) 'run)
             proc)
        (esa-cui::start-process))))

(defun esa-cui::exist-process ()
  (let ((proc (gethash esa-cui::current-team esa-cui::process-hash)))
    (and (processp proc)
         (process-status proc)
         t)))

(defun esa-cui::start-process ()
  (setq esa-cui::response "")
  (let* ((procnm (format "esa-cui:%s" esa-cui::current-team))
         (access-token (gethash esa-cui::current-team esa-cui::access-token-hash))
         (cmd (format "esa-cui login %s -a %s" esa-cui::current-team access-token))
         (proc (start-process-shell-command procnm nil cmd))
         (waiti 0))
    (set-process-filter proc 'esa-cui::receive-response)
    (case system-type
      ((darwin)
       (set-process-coding-system proc 'utf-8-nfd-dos 'utf-8-nfd-unix))
      (t
       (set-process-coding-system proc 'utf-8-dos 'utf-8-unix)))
    (process-query-on-exit-flag proc)
    (while (and (< waiti 50)
                  (not (esa-cui::response-finished-p)))
        (accept-process-output proc 0.2 nil t)
        (incf waiti))
    (puthash esa-cui::current-team proc esa-cui::process-hash)))

(defun esa-cui::stop-process ()
  (when (esa-cui::exist-process)
    (let ((proc (gethash esa-cui::current-team esa-cui::process-hash)))
      (process-send-string proc "exit\n"))))

(defun esa-cui::receive-response (proc res)
  (esa-cui--trace "Received response.\n%s" res)
  (yaxception:$
    (yaxception:try
      (when (stringp res)
        (setq esa-cui::response (concat esa-cui::response res))))
    (yaxception:catch 'error e
      (esa-cui--error "Failed receive response : %s\n%s"
                      (yaxception:get-text e)
                      (yaxception:get-stack-trace-string e)))))

(defun* esa-cui::request (cmdstr &key async)
  (esa-cui--debug "Start request. cmdstr[%s] async[%s]" cmdstr async)
  (cond (async
         (process-send-string (esa-cui::get-process) (concat cmdstr "\n"))
         t)
        (t
         (esa-cui::get-response cmdstr)
         t)))

(defun* esa-cui::get-response (cmdstr &key waitsec)
  (esa-cui--debug "Start get response. cmdstr[%s] waitsec[%s]" cmdstr waitsec)
  (let ((proc (esa-cui::get-process))
        (waiti 0)
        (maxwaiti (* (or waitsec 1) 5)))
    (setq esa-cui::response "")
    (process-send-string proc (concat cmdstr "\n"))
    (esa-cui--trace "Start wait response from server.")
    (while (and (< waiti maxwaiti)
                (not (esa-cui::response-finished-p)))
      (accept-process-output proc 0.2 nil t)
      (incf waiti))
    (cond ((not (< waiti maxwaiti))
           (esa-cui--warn "Timeout get response of %s" cmdstr)
           esa-cui::response)
          (t
           (esa-cui--trace "Got response from server.")
           (replace-match "" nil nil esa-cui::response)))))


(defun esa-cui:exit ()
  (esa-cui::request "exit"))

(defun esa-cui:ls (&optional path)
  (esa-cui::get-response (if path
                             (format "ls '%s'" path)
                           "ls")))

(defun esa-cui:cd (path)
  (esa-cui::request (format "cd '%s'" path)))

(defun* esa-cui:cat (path &key json indent)
  (let ((cmd (format "cat %s%s'%s'"
                     (if json "-json " "")
                     (if indent "" "-noindent ")
                     path)))
    (esa-cui::get-response cmd)))

(defun esa-cui:teams ()
  (loop for k being hash-key in esa-cui::access-token-hash collect k))

(defun esa-cui:set-active-team (team &optional buffer-local-p)
  (if buffer-local-p
      (set (make-local-variable 'esa-cui::current-team) team)
    (setq esa-cui::current-team team)))

;;;###autoload
(defun* esa-cui:regist-team (team &key access-token)
  (puthash team access-token esa-cui::access-token-hash)
  t)


(provide 'esa-cui)