(in-package #:losh)


;;;; Symbols
(defun symbolize (&rest args)
  "Slap `args` together stringishly into a symbol and intern it.

  Example:

    (symbolize 'foo :bar \"baz\")
    => 'foobarbaz

  "
  (intern (format nil "~{~A~}" args)))


;;;; Math
(defparameter tau (coerce (* pi 2) 'single-float)) ; fuck a pi


(defun square (x)
  (* x x))

(defun dividesp (n divisor)
  "Return whether `n` is evenly divisible by `divisor`."
  (zerop (mod n divisor)))


(defun norm (min max val)
  "Normalize `val` to a number between `0` and `1` (maybe).

  If `val` is between `max` and `min`, the result will be a number between `0`
  and `1`.

  If `val` lies outside of the range, it'll be still be scaled and will end up
  outside the 0/1 range.

  "
  (/ (- val min)
     (- max min)))

(defun lerp (from to n)
  "Lerp together `from` and `to` by factor `n`.

  Note that you might want `precise-lerp` instead.

  "
  (+ from
     (* n (- to from))))

(defun precise-lerp (from to n)
  "Lerp together `from` and `to` by factor `n`, precisely.

  Vanilla lerp does not guarantee `(lerp from to 0.0)` will return exactly
  `from` due to floating-point errors.  This version will return exactly `from`
  when given a `n` of `0.0`, at the cost of an extra multiplication.

  "
  (+ (* (- 1 n) from)
     (* n to)))

(defun map-range (source-from source-to dest-from dest-to source-val)
  "Map `source-val` from the source range to the destination range.

  Example:

    ;          source    dest        value
    (map-range 0.0 1.0   10.0 20.0   0.2)
    => 12.0

  "
  (lerp dest-from dest-to
        (norm source-from source-to source-val)))

(defun clamp (from to value)
  "Clamp `value` between `from` and `to`."
  (let ((max (max from to))
        (min (min from to)))
    (cond
      ((> value max) max)
      ((< value min) min)
      (t value))))


;;;; Random
(defun randomp ()
  "Return a random boolean."
  (zerop (random 2)))

(defun random-elt (seq)
  "Return a random element of `seq`, and whether one was available.

  This will NOT be efficient for lists.

  Examples:

    (random-elt #(1 2 3))
    => 1
       T

    (random-elt nil)
    => nil
       nil

  "
  (let ((length (length seq)))
    (if (zerop length)
      (values nil nil)
      (values (elt seq (random length)) t))))

(defun random-range (min max)
  "Return a random number between [`min`, `max`)."
  (+ min (random (- max min))))

(defun random-range-exclusive (min max)
  "Return a random number between (`min`, `max`)."
  (+ 1 min (random (- max min 1))))

(defun random-around (value spread)
  "Return a random number within `spread` of `value`."
  (random-range (- value spread)
                (+ value spread)))

(defun d (n sides &optional (plus 0))
  "Roll some dice.

  Examples:

    (d 1 4)     ; rolls 1d4
    (d 2 8)     ; rolls 2d8
    (d 1 10 -1) ; rolls 1d10-1

  "
  (+ (iterate (repeat n)
              (sum (1+ (random sides))))
     plus))


;;;; Functions
(defun juxt (&rest fns)
  "Return a function that will juxtipose the results of `functions`.

  This is like Clojure's `juxt`.  Given functions `(f0 f1 ... fn)`, this will
  return a new function which, when called with some arguments, will return
  `(list (f0 ...args...) (f1 ...args...) ... (fn ...args...))`.

  Example:

    (funcall (juxt #'list #'+ #'- #'*) 1 2)
    => ((1 2) 3 -1 2)

  "
  (lambda (&rest args)
    (mapcar (rcurry #'apply args) fns)))


;;;; Control Flow
(defmacro recursively (bindings &body body)
  "Execute body recursively, like Clojure's `loop`/`recur`.

  `bindings` should contain a list of symbols and (optional) default values.

  In `body`, `recur` will be bound to the function for recurring.

  Example:

      (defun length (some-list)
        (recursively ((list some-list) (n 0))
          (if (null list)
            n
            (recur (cdr list) (1+ n)))))

  "
  (flet ((extract-var (binding)
           (if (atom binding) binding (first binding)))
         (extract-val (binding)
           (if (atom binding) nil (second binding))))
    `(labels ((recur ,(mapcar #'extract-var bindings)
                ,@body))
      (recur ,@(mapcar #'extract-val bindings)))))


;;;; Mutation
(defmacro zap% (place function &rest arguments &environment env)
  "Update `place` by applying `function` to its current value and `arguments`.

  `arguments` should contain the symbol `%`, which is treated as a placeholder
  where the current value of the place will be substituted into the function
  call.

  For example:

  (zap% foo #'- % 10) => (setf foo (- foo 10)
  (zap% foo #'- 10 %) => (setf foo (- 10 foo)

  "
  ;; original idea/name from http://malisper.me/2015/09/29/zap/
  (assert (find '% arguments)
      ()
    "Placeholder % not included in zap macro form.")
  (multiple-value-bind (temps exprs stores store-expr access-expr)
      (get-setf-expansion place env)
    `(let* (,@(mapcar #'list temps exprs)
            (,(car stores)
             (funcall ,function
                      ,@(substitute access-expr '% arguments))))
      ,store-expr)))

(defmacro mulf (place n)
  "Multiply `place` by `n` in-place."
  `(zap% ,place #'* % ,n))

(defmacro zapf (place function)
  "Update `place` with the result of calling `function` on it."
  `(zap% ,place ,function %))


;;;; Hash Tables
(defmacro gethash-or-init (key hash-table default-form)
  "Get `key`'s value in `hash-table`, initializing if necessary.

  If `key` is in `hash-table`: return its value without evaluating
  `default-form` at all.

  If `key` is NOT in `hash-table`: evaluate `default-form` and insert it before
  returning it.

  "
  ;; TODO: think up a less shitty name for this
  (once-only (key hash-table)
    (with-gensyms (value found)
      `(multiple-value-bind (,value ,found)
        (gethash ,key ,hash-table)
        (if ,found
          ,value
          (setf (gethash ,key ,hash-table) ,default-form))))))


;;;; Queues
;;; Based on the PAIP queues (thanks, Norvig), but beefed up a little bit to add
;;; tracking of the queue size.

(declaim (inline make-queue enqueue dequeue queue-empty-p))

(defstruct (queue (:constructor make-queue%))
  (contents nil :type list)
  (last nil :type list)
  (size 0 :type fixnum))


(defun make-queue ()
  (make-queue%))

(defun queue-empty-p (q)
  (zerop (queue-size q)))

(defun enqueue (item q)
  (let ((cell (cons item nil)))
    (setf (queue-last q)
          (if (queue-empty-p q)
            (setf (queue-contents q) cell)
            (setf (cdr (queue-last q)) cell))))
  (incf (queue-size q)))

(defun dequeue (q)
  (when (zerop (decf (queue-size q)))
    (setf (queue-last q) nil))
  (pop (queue-contents q)))

(defun queue-append (q l)
  (loop :for item :in l
        :for size = (enqueue item q)
        :finally (return size)))


;;;; Iterate
(defmacro-driver (FOR var PAIRS-OF-LIST list)
  "Iterate over the all pairs of the (including (last . first))."
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (current l)
      `(progn
        (with ,l = ,list)
        (with ,current = ,l)
        (,kwd ,var next
         (cond
           ((null ,current)
            (terminate))

           ((null (cdr ,current))
            (prog1
                (cons (first ,current) (car ,l))
              (setf ,current nil)))

           (t
            (prog1
                (cons (first ,current) (second ,current))
              (setf ,current (cdr ,current))))))))))


(defmacro-clause (AVERAGING expr &optional INTO var)
  (with-gensyms (count)
    (let ((average (or var (gensym "average"))))
      `(progn
        (for ,average
             :first ,expr
             ;; continuously recompute the running average instead of keeping
             ;; a running total to avoid bignums when possible
             :then (/ (+ (* ,average ,count)
                         ,expr)
                      (1+ ,count)))
        (for ,count :from 1)
        ,(when (null var)
           ;; todo handle this better
           `(finally (return ,average)))))))

(defmacro-clause (TIMING time-type &optional SINCE-START-INTO var PER-ITERATION-INTO per)
  (let ((timing-function (ecase time-type
                           ((real-time) #'get-internal-real-time)
                           ((run-time) #'get-internal-run-time)))
        (since (or var (gensym))))
    (with-gensyms (start-time current-time previous-time)
      `(progn
        (with ,start-time = (funcall ,timing-function))
        (for ,current-time = (funcall ,timing-function))
        (for ,previous-time :previous ,current-time :initially ,start-time)
        (for ,since = (- ,current-time ,start-time))
        ,(when per
           `(for ,per = (- ,current-time ,previous-time)))
        ,(when (and (null var) (null per))
           `(finally (return ,since)))))))


(defmacro-driver (FOR var IN-LISTS lists)
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (list)
      `(progn
        (generate ,list :in (remove nil (list ,@lists)))
        (,kwd ,var next (progn (when (null ,list)
                                 (next ,list))
                               (pop ,list)))))))


(defun seq-done-p (seq len idx)
  (if idx
    (= idx len)
    (null seq)))

(defmacro-driver (FOR var IN-SEQUENCES seqs)
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (seq len idx)
      `(progn
        (with ,len = nil)
        (with ,idx = nil)
        (generate ,seq :in (remove-if #'emptyp (list ,@seqs)))
        (,kwd ,var next
         (progn
           (when (seq-done-p ,seq ,len ,idx)
             (etypecase (next ,seq)
               (cons (setf ,len nil ,idx nil))
               (sequence (setf ,len (length ,seq)
                               ,idx 0))))
           (if ,idx
             (prog1 (elt ,seq ,idx)
               (incf ,idx))
             (pop ,seq))))))))


;;;; Hash Sets
(defclass hash-set ()
  ((data :initarg :data)))


(defun make-set (&key (test #'eql) (initial-data nil))
  (let ((set (make-instance 'hash-set
                            :data (make-hash-table :test test))))
    (mapcar (curry #'set-add set) initial-data)
    set))


(defun set-contains-p (set value)
  (nth-value 1 (gethash value (slot-value set 'data))))

(defun set-empty-p (set)
  (zerop (hash-table-count (slot-value set 'data))))

(defun set-add (set value)
  (setf (gethash value (slot-value set 'data)) t)
  value)

(defun set-add-all (set seq)
  (map nil (curry #'set-add set) seq))

(defun set-remove (set value)
  (remhash value (slot-value set 'data))
  value)

(defun set-remove-all (set seq)
  (map nil (curry #'set-remove set) seq))

(defun set-clear (set)
  (clrhash (slot-value set 'data))
  set)

(defun set-random (set)
  (if (set-empty-p set)
    (values nil nil)
    (loop :with data = (slot-value set 'data)
          :with target = (random (hash-table-count data))
          :for i :from 0
          :for k :being :the :hash-keys :of data
          :when (= i target)
          :do (return (values k t)))))

(defun set-pop (set)
  (multiple-value-bind (val found) (set-random set)
    (if found
      (progn
        (set-remove set val)
        (values val t))
      (values nil nil))))


(defmethod print-object ((set hash-set) stream)
  (print-unreadable-object (set stream :type t)
    (format stream "~{~S~^ ~}"
            (iterate (for (key nil) :in-hashtable (slot-value set 'data))
                     (collect key)))))


;;;; Debugging & Logging
(defun pr (&rest args)
  (format t "~{~S~^ ~}~%" args)
  (finish-output)
  (values))

(defun bits (n size)
  ;; http://blog.chaitanyagupta.com/2013/10/print-bit-representation-of-signed.html
  (format t (format nil "~~~D,'0B" size) (ldb (byte size 0) n))
  (values))


;;;; File IO
(defun slurp (path)
  "Sucks up an entire file from PATH into a freshly-allocated string,
   returning two values: the string and the number of bytes read."
  (with-open-file (s path)
    (let* ((len (file-length s))
           (data (make-string len)))
      (values data (read-sequence data s)))))

(defun spit (path str)
  "Spit the string into a file at the given path."
  (with-open-file (s path :direction :output :if-exists :supersede)
    (format s "~A" str)))


;;;; dlambda
;;; From Let Over Lambda.
(defmacro dlambda (&rest clauses)
  (with-gensyms (message arguments)
    (flet ((parse-clause (clause)
             (destructuring-bind (key arglist &rest body)
                 clause
               `(,key (apply (lambda ,arglist ,@body) ,arguments)))))
      `(lambda (,message &rest ,arguments)
        (ecase ,message
          ,@(mapcar #'parse-clause clauses))))))
