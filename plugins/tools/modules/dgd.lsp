;;; ==========================================================================
;;;  SDDIMGD (lenh tat DGD) - Dim giao diem: ve 1 duong cat, lenh tu dong dim tung doan giua cac giao diem + dim tong
;;;  Tich hop tu DimGiaoDiem v2 theo yeu cau khach hang (UCS xoay van dung, tra lai bien he thong khi loi / Esc).
;;; ==========================================================================
;;; ---- Tuy chon "chu dim canh duong dim" dung chung cho DGD va DPK (luu trong ban ve, mac dinh BAT) ----
;;; BAT: ep DIMATFIT=1 (Text), DIMTIX=0, DIMTMOVE=0 (Beside the dimension line) khi dim, xong tra lai; TAT: giu nguyen kieu dim cua ban.
(defun sd:dimchu-on () (/= (vlax-ldata-get "SD" "DIMCHU") "TAT"))
(defun sd:dimchu-toggle ()
  (vlax-ldata-put "SD" "DIMCHU" (if (sd:dimchu-on) "TAT" "BAT"))
  (princ (strcat "\n[SD] Chu dim canh duong dim (DIMATFIT 1, DIMTIX 0, DIMTMOVE 0): " (if (sd:dimchu-on) "BAT" "TAT"))))
;; Hoi diem, co tu khoa C de doi tuy chon; base = diem co so (nil neu khong co)
(defun sd:dimchu-pt (msg base / r)
  (setq msg (strcat msg " [Chu dim canh duong dim: " (if (sd:dimchu-on) "BAT" "TAT") " - go C de doi]: "))
  (initget "Chu")
  (setq r (if base (getpoint base msg) (getpoint msg)))
  (while (= r "Chu")
    (sd:dimchu-toggle)
    (initget "Chu")
    (setq r (if base (getpoint base msg) (getpoint msg))))
  r)
(defun sd:dimchu-apply ()
  (if (sd:dimchu-on)
    (progn (setvar "DIMATFIT" 1) (setvar "DIMTIX" 0) (setvar "DIMTMOVE" 0))))

(defun c:SDDIMGD ( / *error* old_os old_echo old_fit old_tix old_tmove undo_on tmp lineobj p1 p2 p3
                     ss i ent r pts uniq p sorted k s ang1 side dirang sp p4)
  (defun *error* (msg)
    (if tmp (progn (entdel tmp) (setq tmp nil)))
    (if undo_on (progn (command "_.UNDO" "_E") (setq undo_on nil)))
    (if old_fit (setvar "DIMATFIT" old_fit))
    (if old_tix (setvar "DIMTIX" old_tix))
    (if old_tmove (setvar "DIMTMOVE" old_tmove))
    (if old_os (setvar "OSMODE" old_os))
    (if old_echo (setvar "CMDECHO" old_echo))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n[SD] Loi: " msg))
    )
    (princ)
  )

  (setq old_os (getvar "OSMODE")
        old_echo (getvar "CMDECHO")
        old_fit (getvar "DIMATFIT")
        old_tix (getvar "DIMTIX")
        old_tmove (getvar "DIMTMOVE"))

  (if (and (setq p1 (sd:dimchu-pt "\nChon diem bat dau cua duong cat" nil))
           (setq p2 (getpoint p1 "\nChon diem ket thuc cua duong cat: "))
           (setq p3 (getpoint p2 "\nChon vi tri dat duong Dim chi tiet: ")))
    (progn
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_BE")
      (setq undo_on T)
      (setvar "OSMODE" 0)
      ;; Dim ron: chu nam canh duong dim, khong ep vao giua 2 duong dong (tra lai khi xong / loi)
      (sd:dimchu-apply)       ;; DIMATFIT 1 / DIMTIX 0 / DIMTMOVE 0 neu tuy chon chu dim dang BAT

      ;; Line tam (WCS) de lay giao diem
      (entmake (list '(0 . "LINE") (cons 10 (trans p1 1 0)) (cons 11 (trans p2 1 0))))
      (setq tmp (entlast))
      (setq lineobj (vlax-ename->vla-object tmp))

      ;; Cac doi tuong cat qua duong cat (fence nhan diem UCS)
      (if (setq ss (ssget "_F" (list p1 p2)))
        (repeat (setq i (sslength ss))
          (setq ent (ssname ss (setq i (1- i))))
          (if (/= ent tmp)
            (progn
              (setq r (vl-catch-all-apply 'vlax-invoke
                        (list (vlax-ename->vla-object ent) 'IntersectWith lineobj 0)))
              (if (and r (not (vl-catch-all-error-p r)))
                (while (>= (length r) 3)
                  (setq pts (cons (trans (list (car r) (cadr r) (caddr r)) 0 1) pts)
                        r (cdddr r))
                )
              )
            )
          )
        )
      )

      (entdel tmp)
      (setq tmp nil)

      ;; Loc diem trung (sai so 0.1)
      (foreach p pts
        (if (not (vl-some '(lambda (x) (< (distance p x) 0.1)) uniq))
          (setq uniq (cons p uniq))
        )
      )
      ;; Sap xep doc duong cat
      (setq sorted (vl-sort uniq '(lambda (a b) (< (distance p1 a) (distance p1 b)))))

      (if (< (length sorted) 2)
        (princ "\n[SD] Duong cat chi di qua duoi 2 diem, khong du de tao Dim!")
        (progn
          ;; 1. Dim chi tiet
          (setq k 0 s "")
          (while (< k (1- (length sorted)))
            (command "_.DIMALIGNED" (nth k sorted) (nth (1+ k) sorted) p3)
            (setq s (strcat s (rtos (distance (nth k sorted) (nth (1+ k) sorted)) 2 2) "  "))
            (setq k (1+ k))
          )
          ;; 2. Dim tong, day ra phia xa duong cat hon dim chi tiet
          (setq ang1 (angle p1 p2)
                side (- (* (- (car p2) (car p1)) (- (cadr p3) (cadr p1)))
                        (* (- (cadr p2) (cadr p1)) (- (car p3) (car p1))))
                dirang (if (< side 0) (- ang1 (/ pi 2)) (+ ang1 (/ pi 2)))
                sp (* 3.5 (getvar "DIMTXT")
                      (if (> (getvar "DIMSCALE") 0) (getvar "DIMSCALE") 1.0))
                p4 (polar p3 dirang sp))
          (command "_.DIMALIGNED" (car sorted) (last sorted) p4)

          (princ (strcat "\n[SD] So doan: " (itoa (1- (length sorted)))
                         " | Tong: " (rtos (distance (car sorted) (last sorted)) 2 2)))
          (princ (strcat "\n[SD] Cac doan: " s))
        )
      )

      (command "_.UNDO" "_E")
      (setq undo_on nil)
      (setvar "DIMATFIT" old_fit)
      (setvar "DIMTIX" old_tix)
      (setvar "DIMTMOVE" old_tmove)
      (setvar "OSMODE" old_os)
      (setvar "CMDECHO" old_echo)
      (princ "\n[SD] Da hoan thanh!")
    )
  )
  (princ)
)
