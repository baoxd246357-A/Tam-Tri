;;; ==========================================================================
;;;  SDDIMPOLY (lenh tat DPK) - Dim tu dong cho polyline kin (co chua cung tron)
;;;  Tich hop tu "LISP DIM TU DONG POLYLINE KIN" v2 theo yeu cau khach hang (ban goc luu o ShopDrawing/goc/DimPolyline_v2.lsp):
;;;  huong ngoai tinh theo dien tich co dau lay mau ca cung, nhan cung bang hinh hoc (chay ca POLYLINE 2D/3D), dung khi UCS xoay,
;;;  *error* tra bien va dong UNDO. Them tuy chon chu dim canh duong dim (sd:dimchu-*, dinh nghia trong dgd.lsp).
;;; ==========================================================================
(defun c:SDDIMPOLY ( / *error* old_vars undo_on ent n i k p1 p2 pm dv ang d_offset
                       ccw pt_dim sum_area pts a b ds r)
  (defun *error* (msg)
    (if old_vars (foreach x old_vars (setvar (car x) (cdr x))))
    (if undo_on (progn (command "_.UNDO" "_E") (setq undo_on nil)))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n[SD] Loi: " msg))
    )
    (princ)
  )

  ;; hoi polyline; go C de doi tuy chon chu dim
  (setq r (progn (initget "Chu")
                 (entsel (strcat "\nChon Polyline kin can Dim tu dong [Chu dim canh duong dim: " (if (sd:dimchu-on) "BAT" "TAT") " - go C de doi]: "))))
  (while (= r "Chu")
    (sd:dimchu-toggle)
    (initget "Chu")
    (setq r (entsel (strcat "\nChon Polyline kin can Dim tu dong [Chu dim canh duong dim: " (if (sd:dimchu-on) "BAT" "TAT") " - go C de doi]: "))))
  (setq ent (if (listp r) (car r)))

  (if (and ent (wcmatch (cdr (assoc 0 (entget ent))) "*POLYLINE"))
    (progn
      (setq old_vars (list (cons "DIMATFIT" (getvar "DIMATFIT"))
                           (cons "DIMTIX" (getvar "DIMTIX"))
                           (cons "DIMTMOVE" (getvar "DIMTMOVE"))
                           (cons "OSMODE" (getvar "OSMODE"))
                           (cons "CMDECHO" (getvar "CMDECHO"))))
      (command "_.UNDO" "_BE")
      (setq undo_on T)
      (sd:dimchu-apply)
      (setvar "OSMODE" 0)
      (setvar "CMDECHO" 0)

      ;; Khoang cach dat Dim = 3.5 lan chieu cao chu
      (setq d_offset (* 3.5 (getvar "DIMTXT")
                        (if (> (getvar "DIMSCALE") 0) (getvar "DIMSCALE") 1.0)))

      ;; Chieu ve: dien tich co dau tren cac diem mau (ca diem tren cung)
      (setq n (fix (+ 0.5 (vlax-curve-getEndParam ent))) i 0 pts nil)
      (while (< i n)
        (foreach k '(0.0 0.25 0.5 0.75)
          (setq pts (cons (vlax-curve-getPointAtParam ent (+ i k)) pts)))
        (setq i (1+ i))
      )
      (setq pts (reverse pts) sum_area 0.0 a (last pts))
      (foreach b pts
        (setq sum_area (+ sum_area (* (- (car b) (car a)) (+ (cadr b) (cadr a)))))
        (setq a b)
      )
      (setq ccw (< sum_area 0)) ;; T neu nguoc chieu kim dong ho

      (setq i 0)
      (while (< i n)
        (setq p1 (vlax-curve-getPointAtParam ent i)
              p2 (vlax-curve-getPointAtParam ent (1+ i))
              pm (vlax-curve-getPointAtParam ent (+ i 0.5))
              dv (vlax-curve-getFirstDeriv ent (+ i 0.5))
              ang (angle '(0.0 0.0 0.0) dv)
              pt_dim (polar pm (if ccw (- ang (/ pi 2)) (+ ang (/ pi 2))) d_offset))
        (if (> (distance p1 p2) 1e-6)
          (progn
            ;; Diem giua duong cong lech khoi trung diem day cung => cung tron
            (setq ds (distance pm (mapcar '(lambda (u v) (/ (+ u v) 2.0)) p1 p2)))
            (if (< ds 1e-4)
              (command "_.DIMALIGNED" "_non" (trans p1 0 1) "_non" (trans p2 0 1)
                       "_non" (trans pt_dim 0 1))
              (command "_.DIMARC" (list ent (trans pm 0 1)) "_non" (trans pt_dim 0 1))
            )
          )
        )
        (setq i (1+ i))
      )
      (princ "\n[SD] Da tao Dim tu dong cho toan bo Polyline!")

      (foreach x old_vars (setvar (car x) (cdr x)))
      (command "_.UNDO" "_E")
      (setq undo_on nil old_vars nil)
    )
    (princ "\n[SD] Doi tuong duoc chon khong phai la Polyline!")
  )
  (princ)
)
