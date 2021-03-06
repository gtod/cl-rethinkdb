(in-package :cl-rethinkdb-reql)

(defmacro r (&body query-form)
  "Wraps query generation in a macro that takes care of pesky function naming
   issues. For instance, the function `count` is reserved in CL, so importing
   cl-rethinkdb-reql:count into your app might mess a lot of things up.
   Instead, you can wrap your queries in (r ...) and use *keywords* for function
   names, and all will be well. For instance:
   
     (r::insert (r::table \"users\") '((\"name\" . \"larry\")))
   
   becomes:
   
     (r (:insert (:table \"users\") '((\"name\" . \"larry\"))))
   
   This allows you to separate CL functions from query functions both logically
   and visually."
  ;; collect all our commands (from defcommand) into a big ol' macrolet form
  ;; that converts keywords into the function equivalents
  (let ((macrolet-forms
          (loop for c in *commands*
                for k = (intern (symbol-name c) :keyword)
                collect `(,k (&rest args)
                           `(,',c ,@args)))))
                
  `(progn
     (macrolet (,@macrolet-forms)
       ,@query-form))))

