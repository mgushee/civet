;;; civet-impl.scm -- implementation code for the civet module.
;;;
;;;   Copyright © 2013 by Matthew C. Gushee <matt@gushee.net> 
;;;   This program is open-source software, released under the
;;;   BSD license. See the accompanying LICENSE file for details.

(import
;  (except scheme
;    string-length string-ref string-set! make-string string substring
;    string->list list->string string-fill! write-char read-char display)
;  (except chicken
;    reverse-list->string print print*)
  (except data-structures
    ->string conc string-chop string-split string-translate
    substring=? substring-ci=? substring-index substring-index-ci)
  (except extras
    read-string write-string read-token))
(import files)
(import posix)
(import utils)
(import srfi-1)
(import srfi-69)
(import irregex)

(use utf8)
(use utf8-srfi-13)
(use ssax)
(use sxpath)
(use sxml-serializer)



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  GLOBAL DEFINITIONS  ----------------------------------------------

(define *site-path* (make-parameter #f))

(define *template-path* (make-parameter #f))

(define *template-cache-path* (make-parameter #f))

(define *enable-l10n* (make-parameter #f))

(define *template-vars* (make-parameter (make-hash-table)))

(define *template-blocks* (make-parameter (make-hash-table)))

(define *civet-ns-prefix* (make-parameter 'cvt))
 
(define *civet-ns-uri* (make-parameter "http://xmlns.therebetygers.net/civet/0.1"))

(define *default-nsmap*
  (make-parameter
    `((#f . "http://www.w3.org/1999/xhtml")
      (,(*civet-ns-prefix*) . ,(*civet-ns-uri*)))))

(define *sxpath-nsmap*
  (make-parameter
    (let ((default-map (*default-nsmap*)))
      (cons
        (cons '*default* (cdar default-map))
        (cdr default-map)))))

(define *sort-functions*
  (make-parameter
    '((string . (string<? string>?))
      (char . (char<? char>?))
      (number . (< >))
      (boolean . ((lambda (a b) (or (not a) b)) (lambda (a b) (or a (not b))))))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  UTILITY FUNCTIONS  -----------------------------------------------

(define (eprintf fmt . args)
  (error (apply sprintf (cons fmt args))))

(define (template-path)
  (or (*template-path*)
      (make-pathname (*site-path*) "templates")))

(define (template-cache-path)
  (or (*template-cache-path*)
      (make-pathname (template-path) ".cache")))
       
(define (alist-merge alist1 alist2)
  (cond
    ((and (not alist1) (not alist2)) '())
    ((not alist1) alist2)
    ((not alist2) alist1)
    (else
      (let ((merge
              (lambda (out-list in-list)
                (let loop ((out out-list)
                           (in in-list))
                  (if (null? in)
                    out
                    (let ((k (caar in))
                          (v (cdar in)))
                      (loop (alist-update k v out) (cdr in))))))))
        (merge (merge '() alist1) alist2)))))

(define (alist-except alist -keys)
  (cond
    ((not alist) '())
    ((not -keys) alist)
    ((eqv? -keys 'all) '())
    (else
      (let loop ((in alist) (out '()))
        (if (null? in)
          out
          (let ((elt (car in))
                (rest (cdr in)))
            (if (memv (car elt) -keys)
              (loop rest out)
              (loop rest (cons elt out)))))))))

(define (update-attrs attrs1 attrs2)
  (cond
    ((and (null? attrs1) (null? attrs2)) #f)
    ((null? attrs1) attrs2)
    ((null? attrs2) attrs1)
    (else
      (let ((delete-dups
              (lambda (keys lst)
                (filter
                  (lambda (elt)
                    (not (member (car elt) keys)))
                  lst)))
            (keys
              (map
                (lambda (elt) (car elt))
                attrs2)))
        (append (delete-dups keys attrs1) attrs2)))))
    
;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  VARIABLE TYPES  --------------------------------------------------

(define (string->bool s)
  (let ((s (string-downcase s)))
    (or (string=? s "t")
        (string=? s "true")
        (string=? s "1"))))

(define (bool->string b #!optional (format 'tc))
  (if b
    (case format
      ((ts) "True")
      ((us) "TRUE")
      ((ls) "true")
      ((uc) "T")
      ((lc) "t")
      ((no) "1")
      (else (eprintf "Unrecognized format symbol '~A" format)))
    (case format
      ((ts) "False")
      ((us) "FALSE")
      ((ls) "false")
      ((uc) "F")
      ((lc) "f")
      ((no) "0")
      (else (eprintf "Unrecognized format symbol '~A" format)))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  TEST EXPRESSION EVALUATOR  ---------------------------------------

;;; A simple expression language for use in cvt:if tests
;;; 
;;; The following types of expressions are supported:
;;;
;;;   <variable-name> [unquoted]:     Return #t if the variable is defined, #f otherwise
;;;   <variable-name> = <value>:      Test equality with equal? . The value may be a quoted
;;;                                   string, a number, or another variable name. 
;;;   <variable-name> != <value>:     Test inequality with equal? . The value may be a quoted
;;;                                   string, a number, or another variable name. 
;;;   lt(<variable-name>, <value>):   Less-than; return #t if variable is less than value, 
;;;                                   #f otherwise.
;;;   gt(<variable-name>, <value>):   Greater-than; return #t if variable is greater than
;;;                                   value, #f otherwise.
;;;   le(<variable-name>, <value>):   Less-than-or-equal-to; return #t if variable is
;;;                                   less than or equvalue, #f otherwise.
;;;   ge(<variable-name>, <value>):   Greater-than-or-equal-to; return #t if variable is
;;;                                   greater than or equal to value, #f otherwise.

(define testexp-re
  (irregex '(: bos (* space)
               (or (=> bare-var (: (or alpha #\_) (+ (or alphanum ("_-:.")))))
                   (: (=> lhs-var (or alpha #\_) (+ (or alphanum ("_-:."))))
                      (* space) (or (=> eq #\=) (=> neq (: #\! #\=))) (* space)
                      (or (=> rhs-var (: (or alpha #\_) (+ (or alphanum ("_-:.")))))
                          (=> rhs-qstring (or (: #\' (=> qstring-val (* any)) #\')
                                          (: #\\ #\" (=> qstring-val (* any)) #\\ #\")))
                          (=> rhs-num (or (+ numeric)
                                          (: (* numeric) #\. (+ numeric))))))
                   (: (=> func (or "lt" "gt" "le" "ge"))
                      (* space) #\( (* space)
                      (=> arg1 (: (or alpha #\_) (+ (or alphanum ("_-:.")))))
                      (* space) #\, (* space)
                      (or (=> arg2-var (: (or alpha #\_) (+ (or alphanum ("_-:.")))))
                          (=> arg2-num (or (+ numeric)
                                           (: (* numeric) #\. (+ numeric)))))
                      (* space) #\)))
               (* space) eos)))
                    
(define (eval-test test-expr ctx)
  (let ((m (irregex-match testexp-re test-expr))
        (ims irregex-match-substring)
        (get-var (lambda (var-name) (ctx 'get-var (string->symbol var-name)))))
    (if m
      (let ((bare-var (ims m 'bare-var))
            (lhs-var (ims m 'lhs-var))
            (func (ims m 'func)))
        (cond
          (bare-var
            (get-var bare-var))
          (lhs-var
            (let* ((lhs-value (get-var lhs-var))
                   (rhs-var (ims m 'rhs-var))
                   (rhs-num (ims m 'rhs-num))
                   (rhs-qstring (ims m 'rhs-qstring))
                   (rhs-value
                     (cond
                       (rhs-var (get-var rhs-var))
                       (rhs-num (string->number rhs-num))
                       (rhs-qstring (ims m 'qstring-val))
                       (else (eprintf "BUG: rhs failed to match rhs-var, rhs-num, or rhs-qstring.\n"))))
                   (test
                     (let ((eq (ims m 'eq))
                           (neq (ims m 'neq)))
                       (cond
                         ((and eq (number? rhs-value)) =)
                         (eq equal?)
                         ((and neq (number? rhs-value)) (lambda (x y) (not (= x y))))
                         (neq (lambda (x y) (not (equal? x y))))
                         (else (eprintf "BUG: Relation is neither '=' nor '!='?!\n"))))))
              (test lhs-value rhs-value)))
          (func
            (let ((test
                    (case (string->symbol func)
                      ((lt) <)
                      ((gt) >)
                      ((le) <=)
                      ((ge) >=)
                      (else (eprintf "Invalid function: '~A'\n" func))))
                  (arg1 (get-var (ims m 'arg1)))
                  (arg2
                    (let ((arg2-var (ims m 'arg2-var))
                          (arg2-num (ims m 'arg2-num)))
                      (cond
                        (arg2-var (get-var arg2-var))
                        (arg2-num (string->number arg2-num))
                        (else (eprintf "Error: invalid argument to function '~A'\n" func))))))
              (test arg1 arg2)))))
      (eprintf "Invalid test expression: '~A'\n" test-expr))))
      
;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  CONTEXT OBJECTS  -------------------------------------------------

;; A context object is a closure encapsulating several alists:
;;   - vars:    containing all in-scope template variables
;;   - attrs:   containing any attributes to be set on the current context node
;;   - nsmap:   containing the mapping of namespace prefixes to URIs
;;   - locale:  containing language, country, encoding, and other localization
;;              parameters
;;   - blocks:  containing template blocks extracted from extension templates
;; --and the 'state' symbol, whose value is one of:
;;     init template head block
(define (make-context #!key (vars '()) (attrs '()) (nsmap (*default-nsmap*))
                      (locale '()) (blocks '()) (state 'init))
  (let ((blocks '()))
    (lambda (cmd . args)
      (case cmd
        ((get-var)
         (alist-ref (car args) vars))
        ((set-var!)
         (alist-update! (car args) (cadr args) vars))
        ((update-vars!)
         (set! vars (alist-merge vars args))) 
        ((set-vars!)
         (set! vars args))
        ((get-vars)
         vars)
        ((get-field)
         (let ((obj (alist-ref (car args) vars)))
           (and obj
                (alist-ref (cadr args) obj))))
        ((pfx->uri)
         (alist-ref (car args) nsmap))
        ((uri->pfx)
         (let ((pair (rassoc (car args) nsmap equal?)))
           (if pair (car pair) #:UNDEFINED)))
        ((set-ns!)
         (alist-update! (car args) (cadr args) vars))
        ((update-nsmap!)
         (set! nsmap (alist-merge nsmap args)))
        ((set-nsmap!)
         (set! nsmap args))
        ((get-nsmap)
         nsmap)
        ((set-attrs!)
         (set! attrs args))
        ((set-attr!)
         (alist-update! (car args) (cadr args) attrs))
        ((get-attrs)
         attrs)
        ((delete-attrs!)
         (set! attrs '()))
        ((get-block)
         (alist-ref (car args) blocks))
        ((set-block!)
         (alist-update! (car args) (cadr args) blocks))
        ((get-blocks)
         blocks)
        ((set-locale!)
         (set! locale (car args)))
        ((set-lang!)
         (alist-update! 'lang (car args) locale))
        ((set-country!)
         (alist-update! 'country (car args) locale))
        ((set-encoding!)
         (alist-update! 'encoding (car args) locale))
        ((set-date-format!)
         (alist-update! 'date-format (car args) locale))
        ((get-locale)
         locale)
        ((set-state!)
         (set! state (car args)))
        ((get-state)
         state)))))


(define (context->context ctx #!key (+vars #f) (-vars #f) (+attrs #f)
                          (-attrs #f) (+nsmap #f) (-nsmap #f)
                          (+locale #f) (-locale #f) (+blocks #f)
                          (-blocks #f) (new-state #f))
  (let ((prev-vars (ctx 'get-vars))
        (prev-attrs (ctx 'get-attrs))
        (prev-nsmap (ctx 'get-nsmap))
        (prev-locale (ctx 'get-locale))
        (prev-blocks (ctx 'get-blocks))
        (prev-state (ctx 'get-state)))
    (make-context vars: (alist-merge (alist-except prev-vars -vars) +vars)
                  attrs: (alist-merge (alist-except prev-attrs -attrs) +attrs)
                  nsmap: (alist-merge (alist-except prev-nsmap -nsmap) +nsmap)
                  locale: (alist-merge (alist-except prev-locale -locale) +locale)
                  blocks: (alist-merge (alist-except prev-blocks -blocks) +blocks)
                  state: (or new-state prev-state))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  TEMPLATE SETS  ---------------------------------------------------

(define (update-cached-template? raw-path cached-path)
  (or (not (file-exists? raw-path))
      (not (file-exists? cached-path))
      (let ((raw-modtime (file-modification-time raw-path))
            (cached-modtime (file-modification-time cached-path)))
        (< cached-modtime raw-modtime))))

(define (load-template name #!optional (nsmap '()))
  (let* ((nsmap* (alist-merge (*default-nsmap*) nsmap))
         (raw-template (make-pathname (template-path) name))
         (sxml-name (pathname-replace-extension name "sxml"))
         (cached-template (make-pathname (template-cache-path) sxml-name))
         (update? (update-cached-template? raw-template cached-template))
         (infile (if update? raw-template cached-template))
         (input (open-input-file infile))
         (sxml
           (if update?
             (ssax:xml->sxml input nsmap*)
             (read input))))
    (close-input-port input)
    (when update?
      (with-output-to-file
        cached-template
        (lambda ()
          (write sxml))))
    sxml))

(define (extension? template)
  (let ((sp (sxpath '(cvt:template) (*sxpath-nsmap*))))
    (not (null? (sp template)))))

(define (get-parent-name template)
  (let ((sp
          (sxpath
            '(cvt:template @ extends *text*)
            (*sxpath-nsmap*))))
    (sp template)))

(define (get-template-locale template)
  (let* ((sp (sxpath '(cvt:template cvt:locale @ *any*) (*sxpath-nsmap*)))
         (locale-data (sp template)))
    (map
      (lambda (elt) (cons (car elt) (cadr elt)))
      locale-data)))

(define (get-template-vars template)
  (let ((sp1 (sxpath '(cvt:template cvt:head cvt:defvar) (*sxpath-nsmap*)))
        (sp2 (sxpath '(@ name *text*))))
    (map
      (lambda (def)
        (let* ((name* (sp2 def))
               (name (string->symbol (car name*))))
          (cons name def)))
      (sp1 template))))

(define (build-template-set name #!optional (nsmap '()))
  (let ((sp1 (sxpath '(cvt:template *)))
        (sp2 (sxpath '(@ name *text*))))
    (let loop ((template (load-template name nsmap))
               (blocks '()))
      (if (extension? template)
        (let ((parent (get-parent-name template)))
          (when (null? parent)
            (eprintf "Parent template '~A' not found.\n" parent))
          (let ((locale (get-template-locale template))
                (vars (get-template-vars template))
                (kids (sp1 template)))
            (loop
              (load-template parent nsmap)
              (foldl
                (lambda (k)
                  (if (eqv? (car k) 'cvt:block)
                    (let* ((name* (sp2 k))
                           (name (string->symbol (car name*))))
                      (if (alist-ref name blocks)
                        blocks
                        (cons (cons name (list locale vars k)) blocks)))
                    blocks))
                blocks kids))))
        (values template blocks)))))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  XML PROCESSING  --------------------------------------------------

(define (get-attrs element)
  (let* ((se (sxpath '(@)))
         (result (se element)))
    (and (not (null? result))
         (car result))))

; input is the entire attributes node: '(@ ((name value) ...))`
(define (get-attval attlist name #!optional (default #f))
  (let* ((se (sxpath `(,name *text*)))
         (result (se attlist)))
    (or (and (not (null? result))
             (car result))
        default)))

(define (get-kids node #!optional (nsmap #f))
  (let* ((default-nsmap (*sxpath-nsmap*))
         (nsmap
           (if nsmap
             (alist-merge default-nsmap nsmap)
             default-nsmap))
         (xp (sxpath '(*any*) nsmap)))
    (xp node)))

(define (except-attlist node #!optional (nsmap #f))
  (let ((kids (get-kids node nsmap)))
    (filter
      (lambda (node)
        (or (not (list? node))
            (not (eqv? (car node) '@))))
      kids)))

;; When encountering a new block, we need to:
;; 1. Check whether a block with the same name is present
;;    in the context, in which case that block will override
;;    this one.
(define (%cvt:block node ctx)
  (let* ((attrs (get-attrs node))
         (content (get-kids node))
         (block-name (get-attval attrs "name"))
         (override (ctx 'get-block block-name)))
    (if override
      (%cvt:block
        override
        (context->context ctx -blocks: (list block-name)))
      (process-tree
        content
        (context->context ctx state: 'block)))))


(define (%cvt:var elt ctx)
  (let* ((attrs (get-attrs elt))
         (var-name (get-attval attrs 'name))
         (obj+field (string-split var-name "."))
         (value
           (if (= (length obj+field) 2)
             (ctx 'get-field (car obj+field) (cadr obj+field))
             (ctx 'get-var (string->symbol var-name))))
         (var-type (get-attval attrs 'type "string"))
         (req-str (get-attval attrs 'required))
         (required (or (not req-str)
                       (string->bool req-str))))
    (cond
      ((and required (not value))
       (eprintf "No value provided for required variable '~A'\n." var-name))
      (value value)
      (else '()))))


(define (%cvt:if node ctx)
  (let* ((attrs (get-attrs node))
         (content (get-kids node))
         (test-expr (get-attval attrs 'test))
         (test-result (eval-test test-expr ctx))
         (else-node
           (let ((se (sxpath '(cvt:else) (*sxpath-nsmap*))))
             (se content))))
    (cond
      (test-result
        (process-tree content (context->context ctx test: #t)))
      ((and (not test-result) else-node)
       (process-tree else-node ctx))
      (else
        '()))))

(define (%cvt:else node ctx)
  '())


(define (register-sort-fun type asc desc)
  (*sort-functions*
    (alist-update type (list asc desc) (*sort-functions*))))

(define (sort-fun type order)
  (let ((type-funs (alist-ref type (*sort-functions*))))
    (cond
      ((not type-funs) (eprintf "No sort function for data type '~A'.\n" type))
      ((eqv? order 'asc) (car type-funs))
      (else (cadr type-funs)))))

(define (%cvt:for node ctx)
  (let* ((attrs (get-attrs node))
         (content (get-kids node))
         (var-name (get-attval attrs "in"))
         (value (ctx 'get-var var-name)))
    (if value
      (let* ((local-key (string->symbol (get-attval attrs "each")))
             (type (get-attval attrs "type" "string"))
             (sort-type (string->symbol (get-attval attrs "sort" "auto")))
             (sort-field (get-attval attrs "sort-field"))
             (order (string->symbol (get-attval attrs "order" "asc")))
             (base-sortfun
               (case sort-type
                 ((alpha) (if (eqv? order 'asc) string<? string>?))
                 ((numeric) (if (eqv? order 'asc) < >))
                 ((auto) (sort-fun type order))))
             (sortfun
               (if sort-field
                 (lambda (ox oy)
                   (let ((fx (alist-ref sort-field ox))
                         (fy (alist-ref sort-field oy)))
                     (base-sortfun fx fy)))
                 base-sortfun)))
        (for-each
          (lambda (elt)
            (process-tree content (context->context +vars: (list (cons local-key elt)))))
          (sort value sortfun))))))

(define (%cvt:with node ctx)
  (let* ((attrs (get-attrs node))
         (content (get-kids node))
         (se (sxpath '(defvar) (*sxpath-nsmap*)))
         (nodes* (se content)))
    (let loop ((nodes nodes*)
               (local-vars '()))
      (if (null? nodes)
        (process-tree content (context->context +vars: local-vars))
        (let* ((defnode (car nodes))
               (var-name (get-attval defnode "name"))
               (value (or (get-attval defnode "value")
                          (get-kids defnode))))
          (loop
            (cdr nodes)
            (cons (cons (string->symbol var-name) value) local-vars)))))))

(define (%cvt:defvar node ctx) #f)

(define (%cvt:locale node ctx) #f)

;; FIXME: seems like there should be a more efficient way to
;;   get the value of a child element
(define (%cvt:attr elt ctx)
  (let* ((name-exp (sxpath '(@name *text*) (*sxpath-nsmap*)))
         (val-exp (sxpath '(@value *text*) (*sxpath-nsmap*)))
         (type-exp (sxpath '(@type *text*) (*sxpath-nsmap*)))
         (fmt-exp (sxpath '(@format *text*) (*sxpath-nsmap*)))
         (if-exp (sxpath '(cvt:if) (*sxpath-nsmap*)))
         (var-exp (sxpath '(cvt:var) (*sxpath-nsmap*)))
         (txt-exp (sxpath '(*text*) (*sxpath-nsmap*)))
         (name (name-exp elt))
         (if-child (if-exp elt))
         (var-child (var-exp elt))
         (txt-child (txt-exp elt))
         (child-value
           (cond
             (if-child (%cvt:if if-child ctx))
             (var-child (%cvt:var var-child ctx)) 
             (txt-child txt-child)
             (else #f)))
         (value (or child-value (val-exp elt))))
    ;; FIXME: This simply uses the raw string value of the attribute,
    ;;   no accounting for type or format
    (list name value))) 

;; Apparently there are no unknown cvt: elements, but I'll keep this
;;   for the time being, just in case.
; (define (%cvt:* attrs content ctx) #f)

(define (%* element ctx)
  (let* ((tag (car element))
         (kids (cdr element))
         (al-exp (sxpath '(@ *) (*sxpath-nsmap*)))
         ; (att-node (al-exp element)) 
         ; (att-list (cdar att-node))
         (att-list* (al-exp element))
         (att-list (map (lambda (attr) (%@* attr ctx)) att-list*))
         (ta-exp (sxpath '(cvt:attr) (*sxpath-nsmap*)))
         (template-attrs (ta-exp element))
         (template-attvals (map (lambda (att-elt) (%cvt:attr att-elt ctx)) template-attrs))
         (final-attvals (update-attrs att-list template-attvals)))
    (if final-attvals
      (cons
        tag
        (cons
          (list '@ final-attvals)
          (process-tree kids ctx)))
      (cons
        tag
        (process-tree kids ctx)))))

(define (%@* attr ctx)
  (let* ((name (car attr))
         (value* (cadr attr))
         (cvtname (cvt-name? name ctx))
         (value
           (if cvtname
             (ctx 'get-var value*)
             value*)))
    (list name value)))

(define (cvt-name? qname ctx)
  (and qname
    (let ((parts (string-split (symbol->string qname) ":")))
      (and (= (length parts) 2)
           (or (string=? (car parts) (*civet-ns-uri*))
               (string=? (ctx 'pfx->uri (string->symbol (car parts)))
                         (*civet-ns-uri*)))
           (cadr parts)))))

;; This is the generic dispatch function
(define (process-tree tree ctx)
  (print "\nPROCESS-TREE:")
  (pp tree)
  (let ((state (ctx 'get-state)))
    (if (or (string? tree) (symbol? tree) (null? tree))
      tree
      (let* ((head (car tree))
             (tail (cdr tree)))
        (cond
          ((null? head)
           (process-tree tail ctx))
          ((string? head)
           (cons head (process-tree tail ctx)))
          ((list? head)
           (filter
             identity
             (map
               (lambda (node) (process-tree node ctx))
               tree)))
          (else
            (let ((cvt-localname (cvt-name? head ctx)))
              (if cvt-localname
                ;; cvt:template should have been handled already by build-template-set
                (case (string->symbol cvt-localname)
                  ((template)
                   (eprintf "The <cvt:template> element cannot occur in a base template"))
                  ((block) (%cvt:block tree ctx)) 
                  ;; cvt:head should already have been handled in build-template-set or
                  ;;   by the handler for the document element
                  ((head) '())
                  ((locale) (%cvt:locale tree ctx))
                  ((defvar) (%cvt:defvar tree ctx))
                  ((var) (%cvt:var tree ctx))
                  ;; cvt:attr should be handled in the handler for its parent element
                  ((attr) '())
                  ((with) (%cvt:with tree ctx))
                  ((if) (%cvt:if tree ctx))
                  ;; cvt:else should already be handled by the %cvt:if handler
                  ((else) '())
                  ((for) (%cvt:for tree ctx)))
                ;; attributes are handled by the handler for their element
                (cond
                  ((eqv? head '@) #f)
                  ((or (eqv? head '*TOP*)
                       (eqv? head '*PI*)
                       (eqv? head '*NAMESPACES*))
                   (cons head (process-tree tail ctx)))
                  ((symbol? head) (%* tree ctx))
                  ((and (not head) (eqv? state 'init))   ; This is probably a default NS annotation
                   (cons head (process-tree tail ctx)))
                  (else
                    (eprintf "Node not handled: ~A\n" head)))))))))))


(define (process-content content ctx)
  ;; content = any content nodes not processed by higher-level handlers
  ;; ctx = context provided by template or block
  ;; 1. process all child nodes
  ;; 2. return result
  ;;
  #f)

(define (process-block block block-data ctx)
  ;; block = the block to be processed
  ;; block-data = alist of blocks
  ;; ctx = context from template level
  ;;
  ;; 1. push state 'block
  ;; 2. check for same block in block-data. If found, remove block from block-data
  ;;    & recurse w/ overriding block
  ;; 3. process content w/ process-content
  ;; 4. pop state
  ;; 5. return transformed content
  ;;
  #f)


(define (process-head head context)
  ;; head = cvt:head element
  ;; context = as provided by template
  ;;
  ;; 1. push state 'head
  ;; 2. read locale data
  ;; 3. read defvars
  ;; 4. pop state
  ;; 5. return new context
  ;;
  #f)

(define (process-base-template template block-data context)
  ;; template = entire base template SXML
  ;; block-data = alist of blocks
  ;; context = as provided by app
  ;;
  ;; 1. push state 'template
  ;; 2. process head (delegate this?)
  ;; 3. process content, including blocks & free elements
  ;; 4. pop state
  ;; 5. return complete tree
  ;;
  ;; Probably best to use SXPath to extract first head, then rest of body.
  (let ((head (car template))
        (tail (cdr template)))
    (cond
      ((list? head)
       (map
         (lambda (node)
           (process-base-template node block-data context))
         template))
      ((eqv? head '*TOP*)
       (cons head (process-base-template tail block-data context)))
      ((or (eqv? head '*PI*)
           (eqv? head '*NAMESPACES*)
           (eqv? head '*COMMENT*)  ; I'm not sure whether this is ever used, but it doesn't hurt to include it
           (eqv? head '@))
       (cons head (process-tree tail context)))
      ((cvt-name? head context)
       (eprintf "The document element of the base template is '~A', which is invalid."))
      (else
        (assert (eqv? (context 'get-state) 'init))
        (let ((child-ctx (context->context context state: 'template +blocks: block-data)))
          (cons head (process-tree tail child-ctx)))))))

(define (process-template-set name context)
  (let-values (((template block-data) (build-template-set name (context 'get-nsmap))))
    (process-base-template template block-data context)))

(define (render template-name context #!key (port #f) (file #f) (nsmap '()))
  (let ((final-tree (process-template-set template-name context)))
    (serialize-sxml final-tree output: (or port file) ns-prefixes: (*sxpath-nsmap*))))


;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ------------------------------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

;;; ========================================================================
;;; ------------------------------------------------------------------------


