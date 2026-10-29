;;; ==========================================================================
;;;  SDDIMPOLY (lenh tat DPK) - Dim tu dong cho polyline kin (co chua cung tron)
;;;  Tich hop tu "LISP DIM TU DONG POLYLINE KIN" theo yeu cau khach hang: ep chu ra ngoai duong dong cho cac goc hep.
;;; ==========================================================================
(defun c:SDDIMPOLY ( / *error* old_vars ent obj n i p1 p2 p_mid deriv ang ccw pt_dim bulge d_offset area_calc_pts sum_area j ptA ptB)
  (defun *error* (msg)
    (if old_vars (mapcar '(lambda (x) (setvar (car x) (cdr x))) old_vars))
    (command "_.UNDO" "_E")
    (princ (strcat "\n[SD] Loi: " msg))
    (princ)
  )

  ;; Luu lai cau hinh bien he thong hien tai
  (setq old_vars (list (cons "DIMATFIT" (getvar "DIMATFIT"))
                       (cons "DIMTIX" (getvar "DIMTIX"))
                       (cons "DIMTMOVE" (getvar "DIMTMOVE"))
                       (cons "OSMODE" (getvar "OSMODE"))
                       (cons "CMDECHO" (getvar "CMDECHO"))))

  (command "_.UNDO" "_BE")

  ;; Ap dung 3 bien he thong de ep Dim tu dong day so nho ra ngoai
  (setvar "DIMATFIT" 1)
  (setvar "DIMTIX" 0)
  (setvar "DIMTMOVE" 0)
  (setvar "OSMODE" 0)
  (setvar "CMDECHO" 0)

  (setq ent (car (entsel "\nChon Polyline kin can Dim tu dong: ")))
  (if (and ent (wcmatch (cdr (assoc 0 (entget ent))) "*POLYLINE"))
    (progn
      (setq obj (vlax-ename->vla-object ent))

      ;; Khoang cach dat Dim van ra ngoai (3.5 lan chieu cao chu hien hanh)
      (setq d_offset (* 3.5 (getvar "DIMTXT") (if (or (= (getvar "DIMSCALE") 0) (= (getvar "DIMSCALE") 1)) 1.0 (getvar "DIMSCALE"))))

      ;; Xac dinh chieu ve cua Polyline (cung hay nguoc chieu kim dong ho)
      (setq area_calc_pts (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 10)) (entget ent))))
      (setq sum_area 0.0 j 0)
      (while (< j (length area_calc_pts))
        (setq ptA (nth j area_calc_pts))
        (setq ptB (nth (rem (1+ j) (length area_calc_pts)) area_calc_pts))
        (setq sum_area (+ sum_area (* (- (car ptB) (car ptA)) (+ (cadr ptB) (cadr ptA)))))
        (setq j (1+ j))
      )
      (setq ccw (< sum_area 0)) ;; True neu ve nguoc chieu kim dong ho

      ;; Vong lap qua tung phan doan cua Polyline
      (setq n (vlax-curve-getEndParam ent) i 0)
      (while (< i n)
        (setq p1 (vlax-curve-getPointAtParam ent i))
        (setq p2 (vlax-curve-getPointAtParam ent (1+ i)))
        (setq p_mid (vlax-curve-getPointAtParam ent (+ i 0.5)))
        (setq deriv (vlax-curve-getFirstDeriv ent (+ i 0.5)))
        (setq ang (angle '(0 0 0) deriv))

        ;; Toa do diem dat Dim luon huong ra phia ngoai Polyline
        (if ccw
          (setq pt_dim (polar p_mid (- ang (/ pi 2)) d_offset))
          (setq pt_dim (polar p_mid (+ ang (/ pi 2)) d_offset))
        )

        ;; Phan doan thang hay cong qua gia tri Bulge
        (setq bulge (vla-GetBulge obj i))
        (if (not (equal p1 p2 1e-6))
          (if (= bulge 0.0)
            ;; Phan doan thang -> DIMALIGNED
            (command "_.DIMALIGNED" "_non" p1 "_non" p2 "_non" pt_dim)
            ;; Phan doan cung tron -> DIMARC
            (command "_.DIMARC" (list ent p_mid) "_non" pt_dim)
          )
        )
        (setq i (1+ i))
      )
      (princ "\n[SD] Da tao Dim tu dong cho toan bo Polyline!")
    )
    (princ "\n[SD] Doi tuong duoc chon khong phai la Polyline!")
  )

  ;; Tra lai cau hinh he thong ban dau
  (mapcar '(lambda (x) (setvar (car x) (cdr x))) old_vars)
  (command "_.UNDO" "_E")
  (princ)
)
