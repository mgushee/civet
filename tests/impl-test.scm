(use test)
(include "../civet-impl.scm")
(include "test-support.scm")

;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  UTILITY FUNCTIONS  -----------------------------------------------
;;; ------  Support data  --------------------------------------------------

(define al1 '())

(define al2
  '((a . "aramaic") (b . "butcher") (c . "chelation")))

(define al3
  '((d . "doldrums") (e . "eschatology") (f . "ferrous")))

(define al4
  '((c . "corpulent") (d . "derivation")))


(define xl1 '())

(define xl2 '(x y z))

(define xl3 '(a b c))

(define xl4 '(c f g))

(define xl5 '(d))


(define ol1 
  '((a . "aramaic") (b . "butcher") (c . "chelation")
    (d . "doldrums") (e . "eschatology") (f . "ferrous")))
 
(define ol2
  '((a . "aramaic") (b . "butcher") (c . "corpulent") (d . "derivation")))

(define ol3
  '((c . "corpulent") (d . "doldrums") (e . "eschatology") (f . "ferrous")))

(define ol4
  '((a . "aramaic") (b . "butcher") (c . "corpulent")
    (d . "doldrums") (e . "eschatology") (f . "ferrous")))

(define ol5 '())

(define ol6 al2)

(define ol7
  '((a . "aramaic") (b . "butcher")))

(define ol8
  '((e . "eschatology") (f . "ferrous")))

(define ol9
  '((a . "aramaic") (b . "butcher") (c . "corpulent")
    (d . "derivation") (e . "eschatology") (f . "ferrous")))

(define ol10
  '((a . "aramaic") (b . "butcher") (d . "doldrums") (e . "eschatology")))

          
;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

(test-group "Utility: alist-merge/alist-except"
  (current-test-comparator alist=?)
  (test "alist-merge with two null lists" al1 (alist-merge al1 al1))
  (test "alist-merge with first list null" al2 (alist-merge al1 al2))
  (test "alist-merge with second list null" al2 (alist-merge al2 al1))
  (test "alist-merge with two identical lists" al2 (alist-merge al2 al2))
  (test "alist-merge with two disjoint lists" ol1 (alist-merge al2 al3))
  (test "alist-merge with two overlapping lists [1]" ol2 (alist-merge al2 al4))
  (test "alist-merge with two overlapping lists [2]" ol3 (alist-merge al4 al3))
  (test "alist-merge an alist-merge result" ol4 (alist-merge (alist-merge al2 al4) al3))
  (test "alist-except with two null lists" ol5 (alist-except al1 xl1))
  (test "alist-except with a null alist & populated xlist" ol5 (alist-except al1 xl2))
  (test "alist-except, deleting all" ol5 (alist-except al2 xl3))
  (test "alist-except with populated alist & null xlist" ol6 (alist-except al2 xl1))
  (test "alist-except with disjoint xlist" ol6 (alist-except al2 xl2))
  (test "alist-except with overlapping xlist" ol7 (alist-except al2 xl4))
  (test "alist-except with single-item xlist" ol8 (alist-except al3 xl5))
  (test "alist-except -> alist-merge -> alist-merge" ol9
        (alist-merge (alist-merge al2 al4) (alist-except al3 xl5)))
  (test "alist-merge -> alist-merge -> alist-except" ol10
        (alist-except (alist-merge (alist-merge al2 al4) al3) xl4))
  (current-test-comparator equal?))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  EXPRESSION LANGUAGE  ---------------------------------------------
;;; ------  Support data  --------------------------------------------------

(define ctx01
  (make-context
    vars: '((aardvark . 219) (berserk . 219.0) (codex . "Silly Putty")
            (darwinism . #f) (elation . '((a . "ay") (b . "bee") (c . "see")))
            (finch . 219) (gastropod . 324) (helium . 323.999)
            (irate . 324.0) (jaguar . #t) (keratin . "Keratin!")
            (louise . #\L) (metanoia . '(3 7 10 9 12 4 13))
            (narwhal . '("alabaster" "brittle" "codicils" "dervish"))
            (oxymoron . '("alabaster" "brittle" "codicils" "dervish"))
            (pernicious . '("dervish" "brittle" "codicils" "alabaster"))
            (quixotic . #t) (rapacious . (vector #\x #\y #\z))
            (serpent . "That's all!") (tenacity . 219.0) (usurper . 324.0)
            (varnish))
    state: 'init))

;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

(test-group "Expression Language"
  (test "Variable defined, true, non-null?    [true ]" #t (not (not (eval-test "oxymoron" ctx01))))
  (test "Variable defined, true, non-null?    [false]" #f (eval-test "zebra" ctx01)) 
  (test "Variable defined, true, non-null?    [false]" #f (eval-test "varnish" ctx01)) 
  (test "Integer variable = integer constant  [true ]" #t (eval-test "aardvark = 219" ctx01))
  (test "Integer variable = integer constant  [false]" #f (eval-test "aardvark = 42" ctx01))
  (test "Integer variable = float constant    [true ]" #t (eval-test "aardvark = 219.0" ctx01))
  (test "Integer variable = float constant    [false]" #f (eval-test "aardvark = 422.03" ctx01))
  (test "Integer variable = integer variable  [true ]" #t (eval-test "aardvark = finch" ctx01))
  (test "Integer variable = integer variable  [false]" #f (eval-test "aardvark = gastropod" ctx01))
  (test "Integer variable = float variable    [true ]" #t (eval-test "aardvark = berserk" ctx01))
  (test "Integer variable = float variable    [false]" #f (eval-test "gastropod = helium" ctx01))
  (test "Integer variable != integer constant [true ]" #t (eval-test "aardvark != 500" ctx01))
  (test "Integer variable != float constant   [false]" #f (eval-test "aardvark != 219.0" ctx01))
  (test "Integer variable != integer constant [false]" #f (eval-test "aardvark != 219" ctx01))
  (test "Integer variable != float constant   [true ]" #t (eval-test "aardvark != 219.1" ctx01))
  (test "Integer variable != integer variable [true ]" #t (eval-test "aardvark != gastropod" ctx01))
  (test "Integer variable != integer variable [false]" #f (eval-test "aardvark != finch" ctx01))
  (test "Integer variable != float variable   [true ]" #t (eval-test "gastropod != helium" ctx01))
  (test "Integer variable != float variable   [false]" #f (eval-test "aardvark != berserk" ctx01))
  (test "Integer variable < integer constant  [true ]" #t (eval-test "lt(gastropod, 1092)" ctx01))
  (test "Integer variable < integer constant  [false]" #f (eval-test "lt(gastropod, 212)" ctx01))
  (test "Integer variable < float constant    [true ]" #t (eval-test "lt(gastropod, 324.0001)" ctx01))
  (test "Integer variable < float constant    [false]" #f (eval-test "lt(gastropod, 219.0)" ctx01))
  (test "Integer variable < integer variable  [true ]" #t (eval-test "lt(finch, gastropod)" ctx01))
  (test "Integer variable < integer variable  [false]" #f (eval-test "lt(gastropod, aardvark)" ctx01))
  (test "Integer variable < float variable    [true ]" #t (eval-test "lt(finch, irate)" ctx01))
  (test "Integer variable < float variable    [false]" #f (eval-test "lt(gastropod, irate)" ctx01))
  (test "Integer variable > integer constant  [true ]" #t (eval-test "gt(gastropod, 212)" ctx01))
  (test "Integer variable > integer constant  [false]" #f (eval-test "gt(gastropod, 1092)" ctx01))
  (test "Integer variable > float constant    [true ]" #t (eval-test "gt(gastropod, 323.9999)" ctx01))
  (test "Integer variable > float constant    [false]" #f (eval-test "gt(aardvark, 219.0)" ctx01))
  (test "Integer variable > integer variable  [true ]" #t (eval-test "gt(gastropod, finch)" ctx01))
  (test "Integer variable > integer variable  [false]" #f (eval-test "gt(aardvark, gastropod)" ctx01))
  (test "Integer variable > float variable    [true ]" #t (eval-test "gt(gastropod, berserk)" ctx01))
  (test "Integer variable > float variable    [false]" #f (eval-test "gt(gastropod, irate)" ctx01))
  (test "Integer variable <= integer constant [true ]" #t (eval-test "le(gastropod, 324)" ctx01))
  (test "Integer variable <= integer constant [false]" #f (eval-test "le(gastropod, 212)" ctx01))
  (test "Integer variable <= float constant   [true ]" #t (eval-test "le(gastropod, 324.0001)" ctx01))
  (test "Integer variable <= float constant   [false]" #f (eval-test "le(gastropod, 219.0)" ctx01))
  (test "Integer variable <= integer variable [true ]" #t (eval-test "le(finch, gastropod)" ctx01))
  (test "Integer variable <= integer variable [false]" #f (eval-test "le(gastropod, aardvark)" ctx01))
  (test "Integer variable <= float variable   [true ]" #t (eval-test "le(gastropod, irate)" ctx01))
  (test "Integer variable <= float variable   [false]" #f (eval-test "le(gastropod, berserk)" ctx01))
  (test "Integer variable >= integer constant [true ]" #t (eval-test "ge(gastropod, 212)" ctx01))
  (test "Integer variable >= integer constant [false]" #f (eval-test "ge(gastropod, 1092)" ctx01))
  (test "Integer variable >= float constant   [true ]" #t (eval-test "ge(gastropod, 324.0)" ctx01))
  (test "Integer variable >= float constant   [false]" #f (eval-test "ge(gastropod, 325.7)" ctx01))
  (test "Integer variable >= integer variable [true ]" #t (eval-test "ge(gastropod, finch)" ctx01))
  (test "Integer variable >= integer variable [false]" #f (eval-test "ge(aardvark, gastropod)" ctx01))
  (test "Integer variable >= float variable   [true ]" #t (eval-test "ge(gastropod, berserk)" ctx01))
  (test "Integer variable >= float variable   [false]" #f (eval-test "ge(aardvark, irate)" ctx01))
  (test "Float variable = integer constant    [true ]" #t (eval-test "berserk = 219" ctx01))
  (test "Float variable = integer constant    [false]" #f (eval-test "berserk = 42" ctx01))
  (test "Float variable = float constant      [true ]" #t (eval-test "berserk = 219.0" ctx01))
  (test "Float variable = float constant      [false]" #f (eval-test "berserk = 422.03" ctx01))
  (test "Float variable = integer variable    [true ]" #t (eval-test "berserk = finch" ctx01))
  (test "Float variable = integer variable    [false]" #f (eval-test "berserk = gastropod" ctx01))
  (test "Float variable = float variable      [true ]" #t (eval-test "tenacity = berserk" ctx01))
  (test "Float variable = float variable      [false]" #f (eval-test "usurper = helium" ctx01))
  (test "Float variable != integer constant   [true ]" #t (eval-test "berserk != 500" ctx01))
  (test "Float variable != float constant     [false]" #f (eval-test "berserk != 219.0" ctx01))
  (test "Float variable != integer constant   [false]" #f (eval-test "berserk != 219" ctx01))
  (test "Float variable != float constant     [true ]" #t (eval-test "berserk != 219.1" ctx01))
  (test "Float variable != integer variable   [true ]" #t (eval-test "berserk != gastropod" ctx01))
  (test "Float variable != integer variable   [false]" #f (eval-test "berserk != finch" ctx01))
  (test "Float variable != float variable     [true ]" #t (eval-test "usurper != helium" ctx01))
  (test "Float variable != float variable     [false]" #f (eval-test "tenacity != berserk" ctx01))
  (test "Float variable < integer constant    [true ]" #t (eval-test "lt(irate, 1092)" ctx01))
  (test "Float variable < integer constant    [false]" #f (eval-test "lt(irate, 212)" ctx01))
  (test "Float variable < float constant      [true ]" #t (eval-test "lt(irate, 324.0001)" ctx01))
  (test "Float variable < float constant      [false]" #f (eval-test "lt(irate, 219.0)" ctx01))
  (test "Float variable < integer variable    [true ]" #t (eval-test "lt(berserk, gastropod)" ctx01))
  (test "Float variable < integer variable    [false]" #f (eval-test "lt(irate, aardvark)" ctx01))
  (test "Float variable < float variable      [true ]" #t (eval-test "lt(berserk, irate)" ctx01))
  (test "Float variable < float variable      [false]" #f (eval-test "lt(usurper, irate)" ctx01))
  (test "Float variable > integer constant    [true ]" #t (eval-test "gt(irate, 212)" ctx01))
  (test "Float variable > integer constant    [false]" #f (eval-test "gt(irate, 1092)" ctx01))
  (test "Float variable > float constant      [true ]" #t (eval-test "gt(irate, 323.9999)" ctx01))
  (test "Float variable > float constant      [false]" #f (eval-test "gt(tenacity, 219.0)" ctx01))
  (test "Float variable > integer variable    [true ]" #t (eval-test "gt(irate, finch)" ctx01))
  (test "Float variable > integer variable    [false]" #f (eval-test "gt(berserk, gastropod)" ctx01))
  (test "Float variable > float variable      [true ]" #t (eval-test "gt(irate, berserk)" ctx01))
  (test "Float variable > float variable      [false]" #f (eval-test "gt(usurper, irate)" ctx01))
  (test "Float variable <= integer constant   [true ]" #t (eval-test "le(irate, 324)" ctx01))
  (test "Float variable <= integer constant   [false]" #f (eval-test "le(irate, 212)" ctx01))
  (test "Float variable <= float constant     [true ]" #t (eval-test "le(irate, 324.0001)" ctx01))
  (test "Float variable <= float constant     [false]" #f (eval-test "le(irate, 219.0)" ctx01))
  (test "Float variable <= integer variable   [true ]" #t (eval-test "le(berserk, gastropod)" ctx01))
  (test "Float variable <= integer variable   [false]" #f (eval-test "le(usurper, aardvark)" ctx01))
  (test "Float variable <= float variable     [true ]" #t (eval-test "le(usurper, irate)" ctx01))
  (test "Float variable <= float variable     [false]" #f (eval-test "le(usurper, berserk)" ctx01))
  (test "Float variable >= integer constant   [true ]" #t (eval-test "ge(usurper, 212)" ctx01))
  (test "Float variable >= integer constant   [false]" #f (eval-test "ge(usurper, 1092)" ctx01))
  (test "Float variable >= float constant     [true ]" #t (eval-test "ge(usurper, 324.0)" ctx01))
  (test "Float variable >= float constant     [false]" #f (eval-test "ge(usurper, 325.7)" ctx01))
  (test "Float variable >= integer variable   [true ]" #t (eval-test "ge(usurper, finch)" ctx01))
  (test "Float variable >= integer variable   [false]" #f (eval-test "ge(tenacity, gastropod)" ctx01))
  (test "Float variable >= float variable     [true ]" #t (eval-test "ge(irate, berserk)" ctx01))
  (test "Float variable >= float variable     [false]" #f (eval-test "ge(berserk, irate)" ctx01)))

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  BASIC SXML PROCESSING  -------------------------------------------
;;; ------------------------------------------------------------------------

;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  SIMPLE TEMPLATE PROCESSING  --------------------------------------
;;; ------  Support data  --------------------------------------------------

;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO


;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  TEMPLATE SET CONSTRUCTION  ---------------------------------------
;;; ------  Support data  --------------------------------------------------

;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO



;;; IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
;;; ----  COMPLEX TEMPLATE PROCESSING  -------------------------------------

;;; ------------------------------------------------------------------------

;;; ========================================================================
;;; ------  Run tests  -----------------------------------------------------

;;; OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO

(test-exit)
