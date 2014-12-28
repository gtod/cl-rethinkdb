(in-package :cl-rethinkdb-reql)

;; -----------------------------------------------------------------------------
;; utils
;; -----------------------------------------------------------------------------
(defun wrap-in-term (object)
  "Make sure a sequence type is wrapped in a term."
  (cond ((typep object 'term)
         object)
        ((and (not (null object))
              (typep object 'object))
         (let ((optargs nil))
           (do-hash/alist ((k v) object)
             (push (cons k (wrap-in-term v)) optargs))
           (term-object optargs)))
        ((and (or (listp object)
                  (vectorp object))
              (not (stringp object))
              (not (null object)))
         (term-array object))
        (t
         (term-from-datum (create-datum object)))))

(defmacro assert-fn-args (reql-function num-args)
  "Assert that a function has the correct number of arguments."
  (let ((fn (gensym "fn")))
    `(let ((,fn ,reql-function))
       (when (is-term +term-term-type-func+ ,fn)
         (assert (eq (num-args ,fn) ,num-args))))))

(defparameter *commands* nil
  "Holds all commands defined with defcommand.")

(defmacro defcommand (name arglist &body body)
  "Simple wrapper for defining commands that pushes the command name into the
   command registry, used by the DSL."
  `(progn
     (cl:delete ',name *commands*)
     (defun ,name ,arglist ,@body)
     (push ',name *commands*)
     ',name))

;; -----------------------------------------------------------------------------
;; manipulating databases
;; -----------------------------------------------------------------------------
(defcommand db-create (db-name)
  "Create a DB."
  (assert (is-string db-name))
  (create-term +term-term-type-db-create+ (list (wrap-in-term db-name))))
  
(defcommand db-drop (db-name)
  "Drop a DB."
  (assert (is-string db-name))
  (create-term +term-term-type-db-drop+ (list (wrap-in-term db-name))))
  
(defcommand db-list ()
  "List DBs."
  (create-term +term-term-type-db-list+))

;; -----------------------------------------------------------------------------
;; manipulating tables
;; TODO: figure out a way to omit database arg (may have to write separate functions)
;; -----------------------------------------------------------------------------
(defcommand table-create (database table-name &key datacenter primary-key durability)
  "Create a table in the given database, optionally specifying the datacenter,
   primary key of the table (default 'id') and table cache size."
  (assert (is-term +term-term-type-db+ database))
  (assert (is-string table-name))
  (assert (or (null datacenter)
              (is-string datacenter)))
  (assert (or (null primary-key)
              (is-string primary-key)))
  (assert (or (null durability)
              (is-string durability)))
  (let ((options nil))
    (when datacenter (push (cons "datacanter" datacenter) options))
    (when primary-key (push (cons "primary_key" primary-key) options))
    (when durability (push (cons "durability" durability) options))
    (create-term +term-term-type-table-create+
                 (list (wrap-in-term database)
                       (wrap-in-term table-name))
                 options)))
    
(defcommand table-drop (database table-name)
  "Drop a table from a database."
  (assert (is-term +term-term-type-db+ database))
  (assert (is-string table-name))
  (create-term +term-term-type-table-drop+
               (list (wrap-in-term database)
                     (wrap-in-term table-name))))

(defcommand table-list (database)
  "List tables in a database."
  (assert (is-term +term-term-type-db+ database))
  (create-term +term-term-type-table-list+ (list (wrap-in-term database))))

(defcommand sync (table)
  "Make sure soft-writes are synced to disk on the given table."
  (assert (is-term +term-term-type-table+ table))
  (create-term +term-term-type-sync+ (list (wrap-in-term table))))

(defcommand index-create (table name &key function multi)
  "Create an index on the table with the given name. If a function is specified,
   that index will be created using the return values of that function for each
   field as opposed to the values of each field."
  (assert (is-term +term-term-type-table+ table))
  (assert (is-string name))
  (assert (or (null function)
              (and (is-function function)
                   (= (num-args function) 1))))
  (assert (is-boolean multi))
  (let ((options nil))
    (when multi (push (cons "multi" t) options))
    (create-term +term-term-type-index-create+
                 (cl:append
                   (list (wrap-in-term table)
                         (wrap-in-term name))
                   (when function
                     (list (wrap-in-term function))))
                 options)))

(defcommand index-drop (table name)
  "Remove an index from a table."
  (assert (is-term +term-term-type-table+ table))
  (assert (is-string name))
  (create-term +term-term-type-index-drop+
               (list (wrap-in-term table)
                     (wrap-in-term name))))

(defcommand index-list (table)
  "List indexes in a table."
  (assert (is-term +term-term-type-table+ table))
  (create-term +term-term-type-index-list+ (list (wrap-in-term table))))

(defcommand index-status (table &rest names)
  "Check the status of the given index on a table (or of all indexes on he given
   table if no name given)."
  (assert (is-term +term-term-type-table+ table))
  (dolist (name names)
    (assert (is-string name)))
  (create-term +term-term-type-index-status+
               (cl:append (list (wrap-in-term table))
                          (mapcar 'wrap-in-term names))))

(defcommand index-wait (table &rest names)
  "Wait for the specified index to be ready (or all indexes if no name
   specified)."
  (assert (is-term +term-term-type-table+ table))
  (dolist (name names)
    (assert (is-string name)))
  (create-term +term-term-type-index-wait+
               (cl:append (list (wrap-in-term table))
                          (mapcar 'wrap-in-term names))))

;; -----------------------------------------------------------------------------
;; writing data
;; -----------------------------------------------------------------------------
(defcommand insert (table sequence/object &key upsert durability return-vals)
  "Create an insert query, given a table object and a set of values.

   The value can be a hash table (or alist), or an array of hashes/alists (in
   the case of a multi-insert)."
  (assert (is-term +term-term-type-table+ table))
  (assert (or (is-sequence sequence/object)
              (is-object sequence/object)))
  (assert (is-boolean upsert))
  (assert (or (null durability)
              (is-string durability)))
  (assert (is-boolean return-vals))
  (let ((options nil))
    (when upsert (push (cons "upsert" t) options))
    (when durability (push (cons "durability" durability) options))
    (when return-vals (push (cons "return_changes" t) options))
    (create-term +term-term-type-insert+
                 (list (wrap-in-term table)
                       (wrap-in-term sequence/object))
                 options)))

(defcommand update (select object/reql-function &key non-atomic durability return-vals)
  "Update an object or set of objects (a select) using the given object or REQL
   function object. Supports using non-atomic writing via :non-atomic."
  (assert (is-select select))
  (assert (or (is-object object/reql-function)
              (and (is-function object/reql-function)
                   (= (num-args object/reql-function) 1))))
  (assert (is-boolean non-atomic))
  (assert (or (null durability)
              (is-string durability)))
  (assert (is-boolean return-vals))
  (let ((options nil))
    (when non-atomic (push (cons "non_atomic" t) options))
    (when durability (push (cons "durability" durability) options))
    (when return-vals (push (cons "return_changes" t) options))
    (create-term +term-term-type-update+
                 (list (wrap-in-term select)
                       (wrap-in-term object/reql-function))
                 options)))

(defcommand replace (select object/reql-function &key non-atomic durability return-vals)
  "Replace an entire object or set of objects (a select) using the given object
   REQL function string. Supports using non-atomic writing via :non-atomic.
   
   The replacement object needs to have the primary key in it."
  (assert (is-select select))
  (assert (or (is-object object/reql-function)
              (and (is-function object/reql-function)
                   (= (num-args object/reql-function) 1))))
  (assert (is-boolean non-atomic))
  (assert (or (null durability)
              (is-string durability)))
  (assert (is-boolean return-vals))
  (let ((options nil))
    (when non-atomic (push (cons "non_atomic" t) options))
    (when durability (push (cons "durability" durability) options))
    (when return-vals (push (cons "return_changes" t) options))
    (create-term +term-term-type-replace+
                 (list (wrap-in-term select)
                       (wrap-in-term object/reql-function))
                 options)))

(defcommand delete (select &key durability return-vals)
  "Delete an object or set of objects (a select)."
  (assert (is-select select))
  (assert (or (null durability)
              (is-string durability)))
  (assert (is-boolean return-vals))
  (let ((options nil))
    (when durability (push (cons "durability" durability) options))
    (when return-vals (push (cons "return_changes" t) options))
    (create-term +term-term-type-delete+
                 (list (wrap-in-term select))
                 options)))

;; -----------------------------------------------------------------------------
;; selecting data
;; -----------------------------------------------------------------------------
(defcommand db (db-name)
  "Create a database object."
  (assert (is-string db-name))
  (create-term +term-term-type-db+ (list (wrap-in-term db-name))))

(defcommand table (table-name &key db use-outdated)
  "Create a table object. Can optionally specify which database the table
   belongs to via :db.
   
   :use-outdated allows you to specify that out-of-date data is ok when querying
   this table."
  (assert (is-string table-name))
  (assert (or (null db)
              (is-term +term-term-type-db+ db)))
  (assert (is-boolean use-outdated))
  (let ((args (list (wrap-in-term table-name))))
    (when db (push (wrap-in-term db) args))
    (create-term +term-term-type-table+
                 args
                 (when use-outdated `(("use_outdated" . ,use-outdated))))))

(defcommand get (table id)
  "Creates a query to grab an object with the given ID (string or int) from the
   given table."
  (assert (is-term +term-term-type-table+ table))
  (assert (is-pkey id))
  (create-term +term-term-type-get+
               (list (wrap-in-term table)
                     (wrap-in-term id))))

(defcommand get-all (table key/keys &key index)
  "Grabs all rows where the given key(s) matches on the given index(es)."
  (let ((keys (if (listp key/keys)
                  key/keys
                  (list key/keys))))
    (assert (is-term +term-term-type-table+ table))
    (dolist (key keys)
      (assert (or (is-datum key)
                  (is-array key))))
    (assert (or (null index)
                (stringp index)))
    (let ((options nil))
      (when index (push (cons "index" index) options))
      (create-term +term-term-type-get-all+
                   (cl:append (list (wrap-in-term table))
                              (mapcar 'wrap-in-term keys))
                   options))))

(defcommand between (select left right &key index left-bound right-bound)
  "Grabs objects from a selection where the primary keys are between two values."
  (assert (is-select select))
  (assert (or (null left)
              (is-pkey left)
              (is-array left)))
  (assert (or (null right)
              (is-pkey right)
              (is-array right)))
  (assert (or (null index)
              (stringp index)))
  (assert (or (null left-bound)
              (string= left-bound "open")
              (string= left-bound "closed")))
  (assert (or (null right-bound)
              (string= right-bound "open")
              (string= right-bound "closed")))
  (let ((options nil))
    (when index (push (cons "index" index) options))
    (when left-bound (push (cons "left_bound" left-bound) options))
    (when right-bound (push (cons "right_bound" right-bound) options))
    (create-term +term-term-type-between+
                 (list (wrap-in-term select)
                       (wrap-in-term left)
                       (wrap-in-term right))
                 options)))

(defcommand filter (sequence object/reql-function &key default)
  "Filter a sequence by either an object or a REQL function."
  (assert (is-sequence sequence))
  (assert (or (is-boolean object/reql-function)
              (is-object object/reql-function)
              (and (is-function object/reql-function)
                   (= (num-args object/reql-function) 1))))
  (assert (is-datum default))
  (let ((options nil))
    (when default (push (cons "default" default) options))
    (create-term +term-term-type-filter+
                 (list (wrap-in-term sequence)
                       (wrap-in-term object/reql-function))
                 options)))

;; -----------------------------------------------------------------------------
;; joins
;; -----------------------------------------------------------------------------
(defcommand inner-join (sequence1 sequence2 reql-function)
  "Perform an inner join on two sequences using the given REQL function."
  (assert (is-sequence sequence1))
  (assert (is-sequence sequence2))
  (assert (is-function reql-function))
  (assert-fn-args reql-function 2)
  (create-term +term-term-type-inner-join+
               (list (wrap-in-term sequence1)
                     (wrap-in-term sequence2)
                     (wrap-in-term reql-function))))
  
(defcommand outer-join (sequence1 sequence2 reql-function)
  "Perform a left outer join on two sequences using the given REQL function."
  (assert (is-sequence sequence1))
  (assert (is-sequence sequence2))
  (assert (is-function reql-function))
  (assert-fn-args reql-function 2)
  (create-term +term-term-type-outer-join+
               (list (wrap-in-term sequence1)
                     (wrap-in-term sequence2)
                     (wrap-in-term reql-function))))
  
(defcommand eq-join (sequence1 field sequence2 &key index)
  "Perform an equality join on two sequences by the given attribute name."
  (assert (is-sequence sequence1))
  (assert (stringp field))
  (assert (is-sequence sequence2))
  (assert (or (null index)
              (stringp index)))
  (let ((options nil))
    (when index (push (cons "index" index) options))
    (create-term +term-term-type-eq-join+
                 (list (wrap-in-term sequence1)
                       (wrap-in-term field)
                       (wrap-in-term sequence2))
                 options)))

(defcommand zip (sequence)
  "Merge left/right fields of each member of a join."
  (assert (is-sequence sequence))
  (create-term +term-term-type-zip+ (list (wrap-in-term sequence))))

;; -----------------------------------------------------------------------------
;; transformations
;; -----------------------------------------------------------------------------
(defcommand map (sequence reql-function)
  "Perform a map (as in map/reduce) on a sequence."
  (assert (is-sequence sequence))
  (assert (is-function reql-function))
  (assert-fn-args reql-function 1)
  (create-term +term-term-type-map+
               (list (wrap-in-term sequence)
                     (wrap-in-term reql-function))))

(defcommand with-fields (sequence &rest paths)
  "Grab only objects in the sequence that have ALL of the specified field names
   and run a pluck() on those fields."
  (assert (is-sequence sequence))
  (dolist (path paths)
    (assert (is-path path)))
  (create-term +term-term-type-with-fields+
               (cl:append (list sequence)
                          (mapcar 'wrap-in-term paths))))

(defcommand concat-map (sequence reql-function)
  "Construct a sequence of all elements returned by the given mapping function."
  (assert (is-sequence sequence))
  (assert (is-function reql-function))
  (assert-fn-args reql-function 1)
  (create-term +term-term-type-concatmap+
               (list (wrap-in-term sequence)
                     (wrap-in-term reql-function))))

(defcommand order-by (sequence field &rest fields)
  "Order a sequence by fields."
  (assert (is-sequence sequence))
  (push field fields)
  (dolist (field fields)
    (assert (is-order field)))
  (create-term +term-term-type-orderby+
               (cl:append (list (wrap-in-term sequence))
                          (mapcar 'wrap-in-term fields))))

(defcommand asc (field)
  "Used in order-by queries to specify a field is ascending in order."
  (assert (stringp field))
  (create-term +term-term-type-asc+
               (list (wrap-in-term field))))

(defcommand desc (field)
  "Used in order-by queries to specify a field is descending in order."
  (assert (stringp field))
  (create-term +term-term-type-desc+
               (list (wrap-in-term field))))

(defcommand skip (sequence number)
  "Skip a number of items in a sequence."
  (assert (is-sequence sequence))
  (assert (is-number number))
  (create-term +term-term-type-skip+
               (list (wrap-in-term sequence)
                     (wrap-in-term number))))

(defcommand limit (sequence number)
  "Limit a sequence by a number."
  (assert (is-sequence sequence))
  (assert (is-number number))
  (create-term +term-term-type-limit+
               (list (wrap-in-term sequence)
                     (wrap-in-term number))))

(defcommand slice (sequence start end)
  "Slice a sequence by a start and end index value."
  (assert (is-sequence sequence))
  (assert (is-number start))
  (assert (is-number end))
  (create-term +term-term-type-slice+
               (list (wrap-in-term sequence)
                     (wrap-in-term start)
                     (wrap-in-term end))))

(defcommand nth (sequence number)
  "Get the nth element of a sequence."
  (assert (is-sequence sequence))
  (assert (is-number number))
  (create-term +term-term-type-nth+
               (list (wrap-in-term sequence)
                     (wrap-in-term number))))

(defcommand indexes-of (sequence datum/reql-function)
  "Get the indexes of all the matching objects."
  (assert (is-sequence sequence))
  (assert (or (is-datum datum/reql-function)
              (and (is-function datum/reql-function)
                   (= (num-args datum/reql-function) 1))))
  (create-term +term-term-type-indexes-of+
               (list (wrap-in-term sequence)
                     (wrap-in-term datum/reql-function))))

(defcommand is-empty (sequence)
  "Returns a boolean indicating if a sequence is empty."
  (assert (is-sequence sequence))
  (create-term +term-term-type-is-empty+ (list (wrap-in-term sequence))))

(defcommand union (sequence &rest sequences)
  "Perform a union on a number of sequences."
  (push sequence sequences)
  (dolist (seq sequences)
    (assert (is-sequence seq)))
  (create-term +term-term-type-union+
               (mapcar 'wrap-in-term sequences)))

(defcommand sample (sequence count)
  "Select a number of elements from the given sequence with uniform
   distribution."
  (assert (is-sequence sequence))
  (assert (is-number count))
  (create-term +term-term-type-sample+
               (list (wrap-in-term sequence)
                     (wrap-in-term count))))

;; -----------------------------------------------------------------------------
;; aggregation
;; -----------------------------------------------------------------------------

(defcommand group (sequence fields-or-functions &key index)
  "Group a sequence by a set of fields or grouping functions."
  (assert (is-sequence sequence))
  (dolist (fof fields-or-functions)
    (assert (or (is-string fof)
                (is-function fof))))
  (assert (or (null index)
              (stringp index)))
  (let ((options nil))
    (when index (push (cons "index" index) options))
    (create-term +term-term-type-group+
                 (cl:append (list (wrap-in-term sequence))
                            (mapcar 'wrap-in-term fields-or-functions))
                 options)))

(defcommand ungroup (grouped-stream)
  "Ungroup a grouped stream."
  (assert (or (is-select grouped-stream)
              (is-array grouped-stream)
              (is-sequence grouped-stream)))
  (create-term +term-term-type-ungroup+
               (list (wrap-in-term grouped-stream))))

(defcommand reduce (sequence reql-function)
  "Perform a reduce on sequence using the given REQL function."
  (assert (is-sequence sequence))
  (assert (is-function reql-function))
  (assert-fn-args reql-function 2)
  (let ((options nil))
    (create-term +term-term-type-reduce+
                 (list (wrap-in-term sequence)
                       (wrap-in-term reql-function))
                 options)))

(defcommand count (sequence &optional datum/reql-function)
  "Counts the items in a sequence."
  (assert (is-sequence sequence))
  (assert (or (null datum/reql-function)
              (is-datum datum/reql-function)
              (and (is-function datum/reql-function)
                   (= (num-args datum/reql-function) 1))))
  (create-term +term-term-type-count+
               (cl:append (list (wrap-in-term sequence))
                          (when datum/reql-function
                            (list (wrap-in-term datum/reql-function))))))

(defmacro define-aggregate-command (name docstring)
  "Makes it super easy to define aggregate commands, since a number of them have
   the same definition."
  `(defcommand ,name (sequence &optional field-or-function)
     ,docstring
     (assert (is-sequence sequence))
     (assert (or (is-string field-or-function)
                 (null field-or-function)
                 (and (is-function field-or-function)
                      (= (num-args field-or-function) 1))))
     (create-term ,(intern (string-upcase (format nil "+term-term-type-~a+" name)) :cl-rethinkdb-proto)
                  (cl:append (list (wrap-in-term sequence))
                             (when field-or-function
                               (list (wrap-in-term field-or-function)))))))

(define-aggregate-command sum "Sum the elements of a sequence.")
(define-aggregate-command avg "Average the elements in a sequence.")
(define-aggregate-command min "Find the minimum of a sequence.")
(define-aggregate-command max "Find the maximum of a sequence.")

(defcommand distinct (sequence)
  "Get all the distinct elements in a sequence (ie remove-duplicates)."
  (assert (is-sequence sequence))
  (create-term +term-term-type-distinct+
               (list (wrap-in-term sequence))))

(defcommand contains (sequence datum-or-fn)
  "Returns whether or not a sequence contains all given values."
  (assert (is-sequence sequence))
  (assert (or (is-datum datum-or-fn)
              (and (is-function datum-or-fn)
                   (assert-fn-args datum-or-fn 1))))
  (create-term +term-term-type-contains+
               (cl:append (list (wrap-in-term sequence)
                                (wrap-in-term datum-or-fn)))))

;; -----------------------------------------------------------------------------
;; document manipulation
;; -----------------------------------------------------------------------------
(defcommand attr (object/sequence field)
  "Grab an object attribute from an object/sequence. Can be nested:

     (attr \"name\" (attr \"user\" (row)))

   Would be r.row(\"user\")(\"name\") in JS."
  (assert (or (is-object object/sequence)
              (is-sequence object/sequence)))
  (assert (is-string field))
  (create-term +term-term-type-get-field+
               (list (wrap-in-term object/sequence)
                     (wrap-in-term field))))

(defcommand row (&optional field)
  "Return a reference to the current row. Optionally takes a string field, in
   which case it pulls thhat field from the row:

     (row \"age\")

   Which is a quicker way of saying:

     (attr \"age\" (row))"
  (assert (or (null field)
              (is-string field)))
  (let ((row (create-term +term-term-type-implicit-var+)))
    (if field
        (attr row field)
        row)))

(defcommand pluck (sequence/object path &rest paths)
  "Given a sequence or object, return a sequence or object with only the given
   path names present."
  (assert (or (is-object sequence/object)
              (is-sequence sequence/object)))
  (push path paths)
  (dolist (path paths)
    (assert (is-path path)))
  (create-term +term-term-type-pluck+
               (cl:append (list (wrap-in-term sequence/object))
                          (mapcar 'wrap-in-term paths))))

(defcommand without (sequence/object path &rest paths)
  "Given a sequence or object, return a sequence or object without the given
   path names present."
  (assert (or (is-object sequence/object)
              (is-sequence sequence/object)))
  (push path paths)
  (dolist (path paths)
    (assert (is-path path)))
  (create-term +term-term-type-without+
               (cl:append (list (wrap-in-term sequence/object))
                          (mapcar 'wrap-in-term paths))))

(defcommand merge (object &rest objects)
  "Merge objects together (merge their fields into one object)."
  (push object objects)
  (dolist (object objects)
    (assert (is-object object)))
  (create-term +term-term-type-merge+
               (mapcar 'wrap-in-term objects)))

(defcommand append (array object)
  "Append an object to the end of an array."
  (assert (is-array array))
  (assert (is-object object))
  (create-term +term-term-type-append+
               (list (wrap-in-term array)
                     (wrap-in-term object))))

(defcommand prepend (array object)
  "Prepend an object to the beginning of an array."
  (assert (is-array array))
  (assert (is-object object))
  (create-term +term-term-type-prepend+
               (list (wrap-in-term array)
                     (wrap-in-term object))))

(defcommand difference (array1 array2)
  "Remove all elements of array2 from array1 and return the resulting array."
  (assert (is-sequence array1))
  (assert (is-sequence array2))
  (create-term +term-term-type-difference+
               (list (wrap-in-term array1)
                     (wrap-in-term array2))))

(defcommand set-insert (array datum)
  "Add the specified datum to the given set, return the resulting set."
  (assert (is-sequence array))
  (assert (is-datum datum))
  (create-term +term-term-type-set-insert+
               (list (wrap-in-term array)
                     (wrap-in-term datum))))

(defcommand set-intersection (array1 array2)
  "Return the intersection of two sets."
  (assert (is-sequence array1))
  (assert (is-sequence array2))
  (create-term +term-term-type-set-intersection+
               (list (wrap-in-term array1)
                     (wrap-in-term array2))))

(defcommand set-union (array1 array2)
  "Return the union of two sets."
  (assert (is-sequence array1))
  (assert (is-sequence array2))
  (create-term +term-term-type-set-union+
               (list (wrap-in-term array1)
                     (wrap-in-term array2))))

(defcommand set-difference (array1 array2)
  "Return the difference of two sets."
  (assert (is-sequence array1))
  (assert (is-sequence array2))
  (create-term +term-term-type-set-difference+
               (list (wrap-in-term array1)
                     (wrap-in-term array2))))

(defcommand has-fields (object path &rest paths)
  (assert (is-object object))
  (push path paths)
  (dolist (path paths)
    (assert (is-path path)))
  (create-term +term-term-type-has-fields+
               (cl:append (list object)
                          (mapcar 'wrap-in-term paths))))

(defcommand insert-at (array index datum)
  "Insert the given object into the array at the specified index."
  (assert (is-array array))
  (assert (is-number index))
  (assert (is-datum datum))
  (create-term +term-term-type-insert-at+
               (list (wrap-in-term array)
                     (wrap-in-term index)
                     (wrap-in-term datum))))

(defcommand splice-at (array1 index array2)
  "Splice an array into another at the given index."
  (assert (is-array array1))
  (assert (is-number index))
  (assert (is-array array2))
  (create-term +term-term-type-splice-at+
               (list (wrap-in-term array1)
                     (wrap-in-term index)
                     (wrap-in-term array2))))

(defcommand delete-at (array index)
  "Remove the element of the array at the given index."
  (assert (is-array array))
  (assert (is-number index))
  (create-term +term-term-type-delete-at+
               (list (wrap-in-term array)
                     (wrap-in-term index))))

(defcommand change-at (array index datum)
  "Change the item in the array at the given index to the given datum."
  (assert (is-array array))
  (assert (is-number index))
  (assert (is-datum datum))
  (create-term +term-term-type-change-at+
               (list (wrap-in-term array)
                     (wrap-in-term index)
                     (wrap-in-term datum))))

(defcommand keys (object)
  "Returns an array of all an object's keys."
  (assert (is-object object))
  (create-term +term-term-type-keys+ (list object)))

(defcommand object (key val &rest args)
  "Create a RDB object from key/value pairs (presented as flat arguments):
     (object \"name\" \"andrew\" \"location\" \"sf\" ...)"
  (push val args)
  (push key args)
  (loop for (key val) on args by #'cddr do
    (assert (is-string key))
    (assert (is-datum val)))
  (create-term +term-term-type-object+
               (mapcar 'wrap-in-term args)))

;; -----------------------------------------------------------------------------
;; math and logic
;; -----------------------------------------------------------------------------
(defcommand + (number/string &rest numbers/strings)
  "Add a set of numbers, or concat a set of strings."
  (push number/string numbers/strings)
  (dolist (number/string numbers/strings)
    (assert (or (is-number number/string)
                (is-string number/string))))
  (create-term +term-term-type-add+
               (mapcar 'wrap-in-term numbers/strings)))

(defcommand - (number &rest numbers)
  "Subtract a set of numbers."
  (push number numbers)
  (dolist (number numbers)
    (assert (is-number number)))
  (create-term +term-term-type-sub+
               (mapcar 'wrap-in-term numbers)))

(defcommand * (number &rest numbers)
  "Multiply a set of numbers."
  (push number numbers)
  (dolist (number numbers)
    (assert (is-number number)))
  (create-term +term-term-type-mul+
               (mapcar 'wrap-in-term numbers)))

(defcommand / (number &rest numbers)
  "Divide a set of numbers."
  (push number numbers)
  (dolist (number numbers)
    (assert (is-number number)))
  (create-term +term-term-type-div+
               (mapcar 'wrap-in-term numbers)))

(defcommand % (number mod)
  "Modulus a number by another."
  (assert (is-number number))
  (assert (is-number mod))
  (create-term +term-term-type-mod+
               (list (wrap-in-term number)
                     (wrap-in-term mod))))

(defcommand && (boolean &rest booleans)
  "Logical and a set of booleans."
  (push boolean booleans)
  (dolist (bool booleans)
    (assert (is-boolean bool)))
  (create-term +term-term-type-all+
               (mapcar 'wrap-in-term booleans)))

(defcommand || (boolean &rest booleans)
  "Logical or a set of booleans."
  (push boolean booleans)
  (dolist (bool booleans)
    (assert (is-boolean bool)))
  (create-term +term-term-type-any+
               (mapcar 'wrap-in-term booleans)))

(defcommand == (object &rest objects)
  "Determine equality of a number of objects."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-eq+
               (mapcar 'wrap-in-term objects)))

(defcommand != (object &rest objects)
  "Determine inequality of a number of objects."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-ne+
               (mapcar 'wrap-in-term objects)))

(defcommand < (object &rest objects)
  "Determine if objects are less than each other."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-lt+
               (mapcar 'wrap-in-term objects)))

(defcommand <= (object &rest objects)
  "Determine if objects are less than/equal to each other."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-le+
               (mapcar 'wrap-in-term objects)))

(defcommand > (object &rest objects)
  "Determine if objects are greater than each other."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-gt+
               (mapcar 'wrap-in-term objects)))

(defcommand >= (object &rest objects)
  "Determine if objects are greater than/equal to each other."
  (push object objects)
  (dolist (object objects)
    (assert (is-datum object)))
  (create-term +term-term-type-ge+
               (mapcar 'wrap-in-term objects)))

(defcommand ~ (boolean)
  "Logical not a boolean value."
  (assert (is-boolean boolean))
  (create-term +term-term-type-not+ (list (wrap-in-term boolean))))

;; -----------------------------------------------------------------------------
;; string manipulation
;; -----------------------------------------------------------------------------
(defcommand match (string string-regex)
  "Returns an object representing a match of the given regex on the given
   string."
  (assert (is-string string))
  (assert (is-string string-regex))
  (create-term +term-term-type-match+
               (list (wrap-in-term string)
                     (wrap-in-term string-regex))))

(defcommand split (string &optional separator max-splits)
  "Split a string. If no separator given, split on whitespace."
  (assert (is-string string))
  (assert (or (null separator)
              (is-string separator)))
  (assert (or (null max-splits)
              (is-number max-splits)))
  (create-term +term-term-type-split+
               (cl:append (list (wrap-in-term string))
                          (when separator (list (wrap-in-term separator)))
                          (when max-splits (list (wrap-in-term max-splits))))))

(defcommand upcase (string)
  "Upcase a string."
  (assert (is-string string))
  (create-term +term-term-type-upcase+ (list (wrap-in-term string))))

(defcommand downcase (string)
  "Downcase a string."
  (assert (is-string string))
  (create-term +term-term-type-downcase+ (list (wrap-in-term string))))

;; -----------------------------------------------------------------------------
;; dates/times
;; -----------------------------------------------------------------------------
(defmacro define-simple-time-command (name docstring)
  "Defines a command that takes one time object as its argument."
  `(defcommand ,name (time)
     ,docstring
     (assert (is-time time))
     (create-term ,(intern (string-upcase (format nil "+term-term-type-~a+" name)) :cl-rethinkdb-proto)
                  (list (wrap-in-term time)))))

(defcommand now ()
  "Return a time object representing the current time (UTC)."
  (create-term +term-term-type-now+))

(defcommand time (timezone year month day &optional hour minute second)
  "Create a new time object witht he given values."
  (assert (or (null timezone)
              (is-string timezone)))
  (assert (is-number year))
  (assert (is-number month))
  (assert (is-number day))
  (assert (or (and (null hour)
                   (null minute)
                   (null second))
              (and (is-number hour)
                   (is-number minute)
                   (is-number second))))
  (create-term +term-term-type-time+
               (list (cl:append (list (wrap-in-term year)
                                      (wrap-in-term month)
                                      (wrap-in-term day))
                                (when hour
                                  (list (wrap-in-term hour)
                                        (wrap-in-term minute)
                                        (wrap-in-term second)))
                                (when timezone
                                  (list (wrap-in-term timezone)))))))

(defcommand epoch-time (timestamp)
  "Create a time object form a timestamp."
  (assert (is-number timestamp))
  (create-term +term-term-type-epoch-time+
               (list (wrap-in-term timestamp))))

(defcommand iso8601 (date &key timezone)
  "Create a time object from an ISO date string (and optionally a timezone)."
  (assert (is-string date))
  (assert (or (null timezone)
              (is-string timezone)))
  (let ((options nil))
    (when timezone (push (cons "default_timezone" timezone) options))
    (create-term +term-term-type-iso8601+
                 (list (wrap-in-term date))
                 options)))

(defcommand in-timezone (time timezone)
  "Return a new time object with a different timezone than the given one."
  (assert (is-time time))
  (assert (is-string timezone))
  (create-term +term-term-type-in-timezone+
               (mapcar 'wrap-in-term (list time timezone))))

(define-simple-time-command timezone "Get a time's timezone (string).")

(defcommand during (time start end)
  "Determine if a time lies withthin the given start/end times."
  (assert (is-time time))
  (assert (is-time start))
  (assert (is-time end))
  (create-term +term-term-type-during+
               (mapcar 'wrap-in-term (list time start end))))

(define-simple-time-command date 
  "Create a new time object fom the given with only y/m/d filled out.")

(define-simple-time-command time-of-day
  "Return the number of seconds elapsed since the beginning of the day stored in
   the time object.")

(define-simple-time-command year "Get a time object's year.")
(define-simple-time-command month "Get a time object's month.")
(define-simple-time-command day "Get a time object's day of month.")
(define-simple-time-command day-of-week "Get a time object's day of week.")
(define-simple-time-command day-of-year "Get a time object's day of year.")
(define-simple-time-command hours "Get a time object's hours")
(define-simple-time-command minutes "Get a time object's minutes")
(define-simple-time-command seconds "Get a time object's seconds")

(define-simple-time-command to-iso8601
  "Return an ISO string of the given time object.")

(define-simple-time-command to-epoch-time
  "Return a unix timestamp for the given time object.")

;; -----------------------------------------------------------------------------
;; control structures
;; -----------------------------------------------------------------------------
(defcommand do (function &rest args)
  "Evaluate the given function in the contex of the given arguments."
  (assert (is-function function))
  (assert-fn-args function (length args))
  (create-term +term-term-type-funcall+
               (cl:append (list (wrap-in-term function))
                          (mapcar 'wrap-in-term args))))

(defcommand branch (bool true-expr false-expr)
  "Given a form that evaluates to a boolean, run the true-expr if it results in
   true, and false-expr if it results in false."
  (assert (is-boolean bool))
  (create-term +term-term-type-branch+
               (list (wrap-in-term bool)
                     (wrap-in-term true-expr)
                     (wrap-in-term false-expr))))

(defcommand foreach (sequence function)
  "Given a sequence, run the given function on each item in the sequence. The
   function takes only one argument."
  (assert (is-sequence sequence))
  (assert (is-function function))
  (assert-fn-args function 1)
  (create-term +term-term-type-foreach+
               (list (wrap-in-term sequence)
                     (wrap-in-term function))))

(defcommand error (message)
  "Throw a runtime error with the given message."
  (assert (is-string message))
  (create-term +term-term-type-error+ (list (wrap-in-term message))))

(defcommand default (top1 top2)
  "Handle non-existence errors gracefully by specifying a default value in the
   case of an error."
  (create-term +term-term-type-default+
               (list (wrap-in-term top1)
                     (wrap-in-term top2))))

(defcommand expr (object)
  "Make sure the passed object is able to be passed as an object in a query."
  (wrap-in-term object))

(defcommand js (javascript-str)
  "Takes a string of javascript and executes it on Rethink's V8 engine. Can also
   evaluate to a function and be used in places where functions are accepted,
   however it is always preferred to us (fn ...) instead."
  (assert (is-string javascript-str))
  (create-term +term-term-type-javascript+ (list (wrap-in-term javascript-str))))

(defcommand coerce-to (object type)
  "Convert the given object to the specified type. To determine the type of an
   object, typeof may be used."
  (assert (is-string type))
  (create-term +term-term-type-coerce-to+
               (list (wrap-in-term object)
                     (wrap-in-term type))))

(defcommand typeof (object)
  "Return the string type of the given object."
  (create-term +term-term-type-typeof+ (list (wrap-in-term object))))

(defcommand info (object)
  "Gets info about any object (tables are a popular choice)."
  (create-term +term-term-type-info+ (wrap-in-term object)))

(defcommand json (string)
  "Convert the given JSON string into a datum."
  (assert (is-string string))
  (create-term +term-term-type-json+ (list (wrap-in-term string))))

(defcommand literal (&optional object)
  "Make sure merge/filter know that the passed object should be taken as a full
   replacement/filter, not a path selector."
  (assert (or (null object)
              (is-object object)))
  (if object
      (create-term +term-term-type-literal+ (list (wrap-in-term object)))
      (create-term +term-term-type-literal+)))

