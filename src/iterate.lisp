(in-package :losh.iterate)

(defmacro expand-iterate-sequence-keywords ()
  '(list
    :from iterate::from
    :upfrom iterate::upfrom
    :downfrom iterate::downfrom
    :to iterate::to
    :downto iterate::downto
    :above iterate::above
    :below iterate::below
    :by iterate::by
    :with-index iterate::with-index))


(defmacro-driver (FOR var MODULO divisor &sequence)
  "Iterate numerically with `var` bound modulo `divisor`.

  This driver iterates just like the vanilla `for`, but each resulting value
  will be modulo'ed by `divisor` before being bound to `var`.

  Note that the modulo doesn't affect the *iteration*, it just affects the
  variable you *see*.  It is as if you had written two clauses:

    (for temp :from foo :to bar)
    (for var = (mod temp divisor))

  Example:

    (iterate (for i            :from 0 :to 20 :by 3) (collect i))
    (0 3 6 9 12 15 18)

    (iterate (for i :modulo 10 :from 0 :to 20 :by 3) (collect i))
    (0 3 6 9  2  5  8)

  "
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (i d)
      `(progn
        (with ,d = ,divisor)
        (generate ,i ,@(expand-iterate-sequence-keywords))
        (,kwd ,var next (mod (next ,i) ,d))))))


(defmacro-driver (FOR var PAIRS-OF-LIST list)
  "Iterate over the all pairs of `list` (including `(last . first)`).

  Examples:

    (iterate (for p :pairs-of-list (list 1 2 3 4))
             (collect p))
    =>
    ((1 . 2) (2 . 3) (3 . 4) (4 . 1))

  "
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

           (t (prog1
                  (cons (first ,current) (second ,current))
                (setf ,current (cdr ,current))))))))))


(defmacro-clause (AVERAGING expr &optional INTO var)
  "Maintain a running average of `expr` in `var`.

  If `var` is omitted the final average will be returned instead.

  Examples:

    (iterate (for x :in '(0 10 0 10))
             (averaging x))
    =>
    5

    (iterate (for x :in '(1.0 1 2 3 4))
             (averaging (/ x 10) :into avg)
             (collect avg))
    =>
    (0.1 0.1 0.13333334 0.17500001 0.22)

  "
  (with-gensyms (count total)
    (let ((average (or var iterate::*result-var*)))
      `(progn
        (for ,count :from 1)
        (sum ,expr :into ,total)
        (for ,average = (/ ,total ,count))))))

(defmacro-clause (TIMING time-type &optional
                  SINCE-START-INTO since-var
                  PER-ITERATION-INTO per-var
                  SECONDS seconds?)
  "Time [real/run]-time into variables.

  `time-type` should be either the symbol `run-time` or `real-time`, depending
  on which kind of time you want to track.  Times are reported in internal time
  units, unless `seconds?` is given, in which case they will be converted to
  a `single-float` by dividing by `internal-time-units-per-second`.

  If `since-var` is given, on each iteration it will be bound to the amount of
  time that has passed since the beginning of the loop.

  If `per-var` is given, on each iteration it will be bound to the amount of
  time that has passed since the last time it was set.  On the first iteration
  it will be bound to the amount of time since the loop started.

  If neither var is given, it is as if `since-var` were given and returned as
  the value of the `iterate` statement.

  `seconds?` is checked at compile time, not runtime.

  Note that the position of this clause in the `iterate` statement matters.
  Also, the code movement of `iterate` can change things around.  Overall the
  results should be pretty intuitive, but if you need absolute accuracy you
  should use something else.

  Examples:

    ; sleep BEFORE the timing clause
    (iterate (repeat 3)
             (sleep 1.0)
             (timing real-time :since-start-into s :per-iteration-into p)
             (collect (list (/ s internal-time-units-per-second 1.0)
                            (/ p internal-time-units-per-second 1.0))))
    =>
    ((1.0003 1.0003)
     (2.0050 1.0047)
     (3.0081 1.0030))

    ; sleep AFTER the timing clause
    (iterate (repeat 3)
             (timing real-time :since-start-into s :per-iteration-into p :seconds t)
             (sleep 1.0)
             (collect (list s p)))
    =>
    ((0.0   0.0)
     (1.001 1.001)
     (2.005 1.004))

  "
  (let ((timing-function (ccase time-type
                           ((:real-time real-time) 'get-internal-real-time)
                           ((:run-time run-time) 'get-internal-run-time)))
        (since-var (or since-var (when (null per-var)
                                   iterate::*result-var*))))
    (flet ((convert (val)
             (if seconds?
               `(/ ,val internal-time-units-per-second 1.0f0)
               val)))
      (with-gensyms (start-time current-time previous-time)
        `(progn
           (with ,start-time = (,timing-function))
           (for ,current-time = (,timing-function))
           ,@(when since-var
               `((for ,since-var = ,(convert `(- ,current-time ,start-time)))))
           ,@(when per-var
               `((for ,previous-time :previous ,current-time :initially ,start-time)
                 (for ,per-var = ,(convert `(- ,current-time ,previous-time))))))))))


(defmacro-driver (FOR var IN-LISTS lists)
  "Iterate each element of each list in `lists` in turn.

  Examples:

    (iterate (with things = (list (list 1 2 3) nil (list :a :b :c)))
             (for val :in-lists things)
             (collect val))
    =>
    (1 2 3 :a :b :c)

  "
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (list)
      `(progn
        (generate ,list :in (remove nil ,lists))
        (,kwd ,var next (progn (when (null ,list)
                                 (next ,list))
                               (pop ,list)))))))


(defun seq-done-p (seq len idx)
  (if idx
    (= idx len)
    (null seq)))

(defmacro-driver (FOR var IN-SEQUENCES seqs)
  "Iterate each element of each sequence in `seqs` in turn.

  Examples:

    (iterate (with things = (list (list 1 2 3) nil #(:a :b :c) #()))
             (for val :in-sequences things)
             (collect val))
    =>
    (1 2 3 :a :b :c)

  "
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (seq len idx)
      `(progn
        (with ,len = nil)
        (with ,idx = nil)
        (generate ,seq :in-whatever (remove-if #'emptyp ,seqs))
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


(defmacro-driver (FOR var AROUND seq)
  "Iterate cyclically around items in the given sequence.

  The results are undefined if the sequence is empty.

  "
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (is-list original source i len)
      `(progn
         (with ,original = ,seq)
         (with ,source = ,original)
         (with ,is-list = (typep ,source 'list))
         (with ,len = (if ,is-list -1 (length ,source)))
         (for ,i :from 0)
         (,kwd ,var next (if ,is-list
                           (progn (unless ,source (setf ,source ,original))
                                  (pop ,source))
                           (progn (when (= ,i ,len) (setf ,i 0))
                                  (elt ,source ,i))))))))



(defclause-sequence ACROSS-FLAT-ARRAY INDEX-OF-FLAT-ARRAY
  :access-fn 'row-major-aref
  :size-fn 'array-total-size
  :sequence-type 'array
  :element-type t)


(defun calculate-array-floors (array)
  (iterate (for (nil . later) :on (array-dimensions array))
           (collect (apply #'* later) :result-type vector)))

(defmacro-driver (FOR binding-form IN-ARRAY array)
  "Iterate over `array`, binding the things in `binding-form` each time.

  This driver iterates over every element in `array`.  Multidimensional arrays
  are supported -- the array will be stepped in row-major order.

  `binding-form` should be a list of `(value ...index-vars...)`.  An index
  variable can be `nil` to ignore it.  Missing index variables are ignored.  If
  no index variables are needed, `binding-form` can simply be the value symbol.

  `generate` is supported.  Call `next` on the value symbol to use it.

  Examples:

    (iterate (for (height x y) :in-array some-2d-heightmap-array)
             (draw-terrain x y height))

    (iterate (for (val nil nil z) :in-array some-3d-array)
             (collect (cons z val)))

    (iterate (for val :in-array any-array)
             (print val))

  "
  (destructuring-bind (var &rest index-vars
                           &aux (kwd (if generate 'generate 'for)))
      (ensure-list binding-form)
    (with-gensyms (i arr dims floors)
      `(progn
        (with ,arr = ,array)
        ,@(when (some #'identity index-vars)
            `((with ,dims = (coerce (array-dimensions ,arr) 'vector))
              (with ,floors = (calculate-array-floors ,arr))))
        (generate ,i :from 0 :below (array-total-size ,arr))
        ,@(iterate (for index :in index-vars)
                   (for dim-number :from 0)
                   (when index
                     (collect `(generate ,index :next
                                (mod (floor ,i (svref ,floors ,dim-number))
                                     (svref ,dims ,dim-number))))))
        (,kwd ,var :next
         (progn
           (next ,i)
           ,@(iterate (for index :in index-vars)
                      (when index (collect `(next ,index))))
           (row-major-aref ,arr ,i)))))))


(defun parse-sequence-arguments
    (from upfrom downfrom to downto above below by)
  (let* ((start (or from upfrom downfrom))
         (end (or to downto above below))
         (increment (or by 1))
         (down (or downfrom downto above))
         (exclusive (or below above))
         (done-p (if exclusive
                   (if down '<= '>=)
                   (if down '< '>)))
         (op (if down '- '+)))
    (values start end increment op done-p)))

(defmacro-driver (FOR var CYCLING on-cycle &sequence)
  "Iterate numerically as with `for`, but cycle around once finished.

  `on-cycle` should be a form to execute every time the number cycles back to
  the beginning.  The value of `var` during this form's execution is undefined.

  `generate` is supported.

  Results are undefined if the cycle doesn't contain at least one number.

  Examples:

    (iterate (repeat 10)
             (for x :cycling t :from 0 :to 3)
             (collect x))
    =>
    (0 1 2 3 0 1 2 3 0 1)

    (iterate (repeat 5)
             (for x :cycling (print 'beep) :from 1 :downto 0 :by 0.5)
             (print x))
    =>
    1.0
    0.5
    0.0
    BEEP
    1.0
    0.5

  "
  (declare (ignore iterate::with-index))
  (multiple-value-bind (start end increment op done-p)
      (parse-sequence-arguments iterate::from iterate::upfrom iterate::downfrom
                                iterate::to iterate::downto
                                iterate::above iterate::below
                                iterate::by)
    (let ((kwd (if generate 'generate 'for)))
      (with-gensyms (%counter %start %end %increment)
        `(progn
          (with ,%end = ,end)
          (with ,%increment = ,increment)
          (with ,%counter)
          ;; ugly hack to get numeric contagion right for the first val
          ;; (borrowed from Alexandria)
          (with ,%start = (- (+ ,start ,%increment) ,%increment))
          (,kwd ,var next
           (progn
             (setf ,%counter
                   (if-first-time ,%start (,op ,%counter ,%increment)))
             (if (,done-p ,%counter ,%end)
               (prog1
                   (setf ,%counter ,%start)
                 ,on-cycle)
               ,%counter))))))))


(defmacro-clause (GENERATE-NESTED forms CONTROL-VAR control-var)
  (iterate
    (for (var . args) :in forms)
    (for prev :previous var :initially nil)

    ;; we basically turn
    ;;   (for-nested ((x :from 0 :to n)
    ;;                (y :from 0 :to m)
    ;;                (z :from 0 :to q)))
    ;; into
    ;;   (generate x :from 0 :to n)
    ;;   (generate y :cycling (next x) :from 0 :to m)
    ;;   (generate z :cycling (next y) :from 0 :to q)
    ;;   (generate control-var
    ;;     :next (if-first-time
    ;;             (progn (next x) (next y) (next z))
    ;;             (next z)))
    (collect var :into vars)
    (collect `(generate ,var
               ,@(when prev `(:cycling (next ,prev)))
               ,@args)
             :into cycling-forms)

    (finally (return `(progn
                       ,@cycling-forms
                       (declare (ignorable ,control-var))
                       (generate ,control-var :next
                                 (if-first-time
                                   (progn ,@(iterate (for v :in vars)
                                                     (collect `(next ,v))))
                                   (next ,var))))))))

(defmacro-clause (FOR-NESTED forms)
  "Iterate the given `forms` in a nested fashion.

   `forms` should be a list of iteration forms.  Each one should have the same
   format as a standard `(for var ...)` numeric iteration clause, but WITHOUT
   the `for`.

   The forms will iterate numerically as if in a series of nested loops, with
   later forms cycling around as many times as is necessary.

   Examples:

    (iterate (for-nested ((x :from 0 :to 3)
                          (y :from 0 :below 1 :by 0.4)))
             (print (list x y)))
    =>
    (0 0)
    (0 0.4)
    (0 0.8)
    (1 0)
    (1 0.4)
    (1 0.8)
    (2 0)
    (2 0.4)
    (2 0.8)
    (3 0)
    (3 0.4)
    (3 0.8)

   "
  (with-gensyms (control)
    `(progn
      (generate-nested ,forms :control-var ,control)
      (next ,control))))


(defmacro-clause (FOR delta-vars WITHIN-RADIUS radius &optional
                  SKIP-ORIGIN should-skip-origin
                  ORIGIN origin)
  "Iterate through a number of delta values within a given radius.

  Imagine you have a 2D array and you want to find all the neighbors of a given
  cell:

     .........
     ...nnn...
     ...nXn...
     ...nnn...
     .........

  You'll need to iterate over the cross product of the array indices from
  `(- target 1)` to `(+ target 1)`.

  You may want to have a larger radius, and you may or may not want to include
  the origin (delta `(0 0)`).

  This clause handles calculating the deltas for you, without needless consing.

  Examples:

    (iterate (for (x) :within-radius 2)
             (collect (list x)))
    =>
    ((-2) (-1) (0) (1) (2))

    (iterate (for (x y) :within-radius 1 :skip-origin t)
             (collect (list x y)))
    =>
    ((-1 -1)
     (-1  0)
     (-1  1)
     ( 0 -1)
     ( 0  1)
     ( 1 -1)
     ( 1  0)
     ( 1  1))

    (iterate (for (x y z) :within-radius 3)
             (collect (list x y z)))
    =>
    ; ... a bigass list of deltas,
    ; the point it is works in arbitrary dimensions.

  "
  (let* ((delta-vars (ensure-list delta-vars))
         (origin-vars (mapcar (lambda (dv) (gensym (mkstr 'origin- dv)))
                              delta-vars))
         (origin-vals (if (null origin)
                        (mapcar (constantly 0) delta-vars)
                        origin)))
    (with-gensyms (r control skip)
      `(progn
         (with ,r = ,radius)
         ,@(mapcar (lambda (ovar oval)
                     `(with ,ovar = ,oval))
                   origin-vars origin-vals)
         (generate-nested ,(iterate (for var :in delta-vars)
                                    (for orig :in origin-vars)
                                    (collect `(,var :from (- ,orig ,r) :to (+ ,orig ,r))))
                          :control-var ,control)
         (next ,control)
         ,@(unless (null should-skip-origin)
             `((with ,skip = ,should-skip-origin)
               (when (and ,skip
                          ,@(iterate (for var :in (ensure-list delta-vars))
                                     (collect `(zerop ,var))))
                 (next ,control))))))))


(defmacro-driver (FOR var EVERY-NTH n DO form)
  "Iterate `var` numerically modulo `n` and run `form` every `n`th iteration.

  The driver can be used to perform an action every N times through the loop.

  `var` itself will be a counter that counts up from to to `n - 1`.

  `generate` is supported.

  Example:

    (iterate (for i :from 1 :to 7)
             (print `(iteration ,i))
             (for tick :every-nth 3 :do (print 'beep))
             (print `(tick ,tick)) (terpri))
    ; =>
    (ITERATION 1)
    (TICK 0)

    (ITERATION 2)
    (TICK 1)

    (ITERATION 3)
    BEEP
    (TICK 2)

    (ITERATION 4)
    (TICK 0)

    (ITERATION 5)
    (TICK 1)

    (ITERATION 6)
    BEEP
    (TICK 2)

    (ITERATION 7)
    (TICK 0)

  "
  (let ((kwd (if generate 'generate 'for)))
    (with-gensyms (counter limit)
      `(progn
        (with ,limit = ,n)
        (generate ,counter :modulo ,limit :from 0)
        (,kwd ,var :next (prog1 (next ,counter)
                           (when (= ,counter (1- ,limit))
                             ,form)))))))


(defmacro-clause (COLLECT-HASH key-and-value &optional
                  INTO var
                  TEST (test '#'eql))
  "Collect keys and values into a hash table at `var`.

  If `var` is omitted the hash table will be returned instead.

  `key-and-value` should be a list of `(key-expr value-expr)`.

  `test` specifies the test used for the hash table.

  Example:

    (iterate (for x :from 0)
             (for y :in '(a b c))
             (collect-hash ((1+ x) y)))
    ; => {1 a
    ;     2 b
    ;     3 c}

  "
  (destructuring-bind (key value) key-and-value
    (let ((hash-table (or var iterate::*result-var*)))
      `(progn
         (with ,hash-table = (make-hash-table :test ,test))
         (setf (gethash ,key ,hash-table) ,value)))))

(defmacro-clause (ORING expr &optional INTO var)
  (let ((result (or var iterate::*result-var*)))
    `(reducing ,expr :by #'or :into ,result :initial-value nil)))

(defmacro-clause (ANDING expr &optional INTO var)
  (let ((result (or var iterate::*result-var*)))
    `(reducing ,expr :by #'and :into ,result :initial-value t)))


(defun keywordize-clause (clause)
  (iterate
    (for (k v . nil) :on clause :by #'cddr)
    (collect (ensure-keyword k))
    (collect v)))

(defun keywordize-some-of-clause (clause)
  ; please kill me
  (append (take 2 clause) (keywordize-clause (nthcdr 2 clause))))

(defun macroexpand-iterate (clause)
  "Macroexpand the given iterate clause/driver.

  Example:

    (macroexpand-iterate '(averaging (+ x 10) :into avg))
    =>
    (PROGN
     (FOR #:COUNT630 :FROM 1)
     (SUM (+ X 10) :INTO #:TOTAL631)
     (FOR AVG = (/ #:TOTAL631 #:COUNT630)))

  "
  ;; Given a clause like (for foo in-whatever bar) we need to:
  ;;
  ;; 1. Look up the appropriate macro (confusingly named via gentemp).  This
  ;;    requires calling `iterate::get-clause-info` with an appropriately-formed
  ;;    clause.
  ;;
  ;;    The first item in the clause must be a normal (non-keyword) symbol, but
  ;;    the rest of the clause keywords must be actual keyword symbols.
  ;;
  ;; 2. Build the appropriate list to `macroexpand-1`.  This should be of the
  ;;    form `(the-wierdly-named-macro ...)`.
  ;;
  ;;    Note that the macro will be expecting the clause to come in as keyword
  ;;    arguments, so unlike in step 1 ALL the clause keywords need to be actual
  ;;    keywords, including the first.
  ;;
  ;; We'll also bind `iterate::*result-var*` so any macros that use it won't
  ;; immediately shit the bed.
  (let ((iterate::*result-var* 'iterate::*result-var*))
    (values
      (macroexpand-1 (cons (iterate::clause-info-function
                             (iterate::get-clause-info
                               (keywordize-some-of-clause clause)))
                           (keywordize-clause clause))))))


(defmacro-driver (FOR var IN-HASHSET hset)
  (let ((kwd (if generate 'generate 'for)))
    `(,kwd (,var) :in-hashtable (losh.hash-sets::hash-set-storage ,hset))))

(defmacro-driver (FOR var RECURSIVELY expr INITIALLY init)
  (let ((kwd (if generate 'generate 'for)))
    `(progn
       (initially (setf ,var ,init))
       (,kwd ,var = ,expr))))

