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
(defun sd:dimchu-msg (msg)
  (strcat msg " [Chu dim canh duong dim: " (if (sd:dimchu-on) "BAT" "TAT") " (C) / Kieu dim ShopDrawing: " (if (sd:dimkieu-on) "BAT" "TAT") " (K)]: "))
(defun sd:dimchu-pt (msg0 base / r msg)
  (setq msg (sd:dimchu-msg msg0))
  (initget "Chu Kieu")
  (setq r (if base (getpoint base msg) (getpoint msg)))
  (while (member r '("Chu" "Kieu"))
    (if (= r "Chu") (sd:dimchu-toggle) (sd:dimkieu-toggle))
    (setq msg (sd:dimchu-msg msg0))
    (initget "Chu Kieu")
    (setq r (if base (getpoint base msg) (getpoint msg))))
  r)

;;; Tuy chon "kieu dim ShopDrawing" (mac dinh BAT): dim bang dimstyle SD-1-<ty le> tren layer SD-KICHTHUOC (tick kien truc, chu 2.5, lam tron 0 so le)
;;; giong cac dim khac cua ShopDrawing; TAT: dung kieu dim hien hanh. Chi co tac dung khi co ham sd:use-dimstyle (ShopDrawing / SDOpLat).
(defun sd:dimkieu-on () (/= (vlax-ldata-get "SD" "DIMKIEU") "TAT"))
(defun sd:dimkieu-toggle ()
  (vlax-ldata-put "SD" "DIMKIEU" (if (sd:dimkieu-on) "TAT" "BAT"))
  (princ (strcat "\n[SD] Kieu dim ShopDrawing (dimstyle SD-1-ty le, layer SD-KICHTHUOC): " (if (sd:dimkieu-on) "BAT" "TAT"))))
;; Chuyen sang kieu dim SD; tra ve (dimstyle-cu layer-cu) de tra lai bang sd:dimkieu-end (nil neu khong dung)
(defun sd:dimkieu-begin ( / old)
  (if (and (sd:dimkieu-on) (boundp 'sd:use-dimstyle) (numberp *SD:SCALE*) (> *SD:SCALE* 0))
    (progn
      (if (boundp 'sd:ensure) (sd:ensure))
      (setq old (list (getvar "DIMSTYLE") (getvar "CLAYER")))
      (sd:use-dimstyle *SD:SCALE*)
      (if (tblsearch "LAYER" "SD-KICHTHUOC") (setvar "CLAYER" "SD-KICHTHUOC"))
      old)))
(defun sd:dimkieu-end (old)
  (if old
    (progn
      (if (tblsearch "LAYER" (cadr old)) (setvar "CLAYER" (cadr old)))
      (if (and (tblsearch "DIMSTYLE" (car old)) (/= (strcase (getvar "DIMSTYLE")) (strcase (car old))))
        (command "_.-DIMSTYLE" "_R" (car old))))))


;; Dim doan ngan (chu khong du cho, nhay ra ngoai): thu nho chu cho vua doan (0.75 / 0.6 / 0.45 lan), khong de chu de len doan ke ben (chi khi tuy chon BAT).
;; Goi truoc moi lenh dim, sau do tra DIMTXT ve gia tri cu. Tra ve he so da dung (de in chan doan).
(defun sd:dimchu-small (len / sc h n fs f r)
  (setq r 1.0)
  (if (sd:dimchu-on)
    (progn
      (setq sc (if (> (getvar "DIMSCALE") 0) (getvar "DIMSCALE") 1.0)
            h (* (getvar "DIMTXT") sc)
            n (strlen (rtos len 2 (getvar "DIMDEC")))
            fs '(1.0 0.75 0.6 0.45) r nil)
      ;; chu rong khoang 0.8 * cao moi ky tu, cong 2 khoang DIMGAP hai ben
      (while (and fs (not r))
        (setq f (car fs) fs (cdr fs))
        (if (>= len (+ (* n 0.8 h f) (* 2.0 (getvar "DIMGAP") sc))) (setq r f)))
      (if (not r) (setq r 0.45))
      (if (< r 1.0) (setvar "DIMTXT" (* r (getvar "DIMTXT"))))))
  r)
(defun sd:dimchu-apply ()
  (if (sd:dimchu-on)
    (progn (setvar "DIMATFIT" 1) (setvar "DIMTIX" 0) (setvar "DIMTMOVE" 0))))

(defun c:SDDIMGD ( / *error* old_os old_echo old_fit old_tix old_tmove old_txt txt0 dk undo_on tmp lineobj p1 p2 p3
                     ss i ent r pts uniq p sorted k s ang1 side dirang sp p4)
  (defun *error* (msg)
    (if tmp (progn (entdel tmp) (setq tmp nil)))
    (if undo_on (progn (command "_.UNDO" "_E") (setq undo_on nil)))
    (if old_txt (setvar "DIMTXT" old_txt))
    (if old_fit (setvar "DIMATFIT" old_fit))
    (if old_tix (setvar "DIMTIX" old_tix))
    (if old_tmove (setvar "DIMTMOVE" old_tmove))
    (if dk (progn (sd:dimkieu-end dk) (setq dk nil)))
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
        old_tmove (getvar "DIMTMOVE")
        old_txt (getvar "DIMTXT"))

  (if (and (setq p1 (sd:dimchu-pt "\nChon diem bat dau cua duong cat" nil))
           (setq p2 (getpoint p1 "\nChon diem ket thuc cua duong cat: "))
           (setq p3 (getpoint p2 "\nChon vi tri dat duong Dim chi tiet: ")))
    (progn
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_BE")
      (setq undo_on T)
      (setvar "OSMODE" 0)
      ;; Dim ron: chu nam canh duong dim, khong ep vao giua 2 duong dong (tra lai khi xong / loi)
      (setq dk (sd:dimkieu-begin))   ;; kieu dim ShopDrawing (neu BAT)
      (setq txt0 (getvar "DIMTXT"))  ;; chieu cao chu cua kieu dim dang dung (sau khi chuyen kieu)
      (sd:dimchu-apply)       ;; DIMATFIT 1 / DIMTIX 0 / DIMTMOVE 0 neu tuy chon chu dim dang BAT
      (princ (strcat "\n[SD] Dim: kieu " (getvar "DIMSTYLE") ", DIMTXT " (rtos (getvar "DIMTXT") 2 2) ", DIMSCALE " (rtos (getvar "DIMSCALE") 2 2)
                     ", DIMATFIT " (itoa (getvar "DIMATFIT")) ", DIMTMOVE " (itoa (getvar "DIMTMOVE")) ", layer " (getvar "CLAYER")))

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
            (sd:dimchu-small (distance (nth k sorted) (nth (1+ k) sorted)))
            (command "_.DIMALIGNED" (nth k sorted) (nth (1+ k) sorted) p3)
            (setvar "DIMTXT" txt0)
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
      (setvar "DIMTXT" old_txt)
      (setvar "DIMATFIT" old_fit)
      (setvar "DIMTIX" old_tix)
      (setvar "DIMTMOVE" old_tmove)
      (if dk (progn (sd:dimkieu-end dk) (setq dk nil)))
      (setvar "OSMODE" old_os)
      (setvar "CMDECHO" old_echo)
      (princ "\n[SD] Da hoan thanh!")
    )
  )
  (princ)
)
