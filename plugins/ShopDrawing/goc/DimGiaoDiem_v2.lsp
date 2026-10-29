;;; LISP DIM GIAO ĐIỂM (CẮT DIM TỰ ĐỘNG) - v2
;;; Lệnh: DGD (Dim Giao Điểm)
;;; v2: đúng khi UCS xoay, *error* đóng UNDO/xoá line tạm/trả biến hệ thống,
;;;     không rò biến toàn cục, in từng đoạn 2 số lẻ để đối chiếu làm tròn.
(vl-load-com)
(defun c:DGD ( / *error* old_os old_echo undo_on tmp lineobj p1 p2 p3
                 ss i ent r pts uniq p sorted k s ang1 side dirang sp p4)
  (defun *error* (msg)
    (if tmp (progn (entdel tmp) (setq tmp nil)))
    (if undo_on (progn (command "_.UNDO" "_E") (setq undo_on nil)))
    (if old_os (setvar "OSMODE" old_os))
    (if old_echo (setvar "CMDECHO" old_echo))
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLỗi: " msg))
    )
    (princ)
  )

  (setq old_os (getvar "OSMODE")
        old_echo (getvar "CMDECHO"))

  (if (and (setq p1 (getpoint "\nChọn điểm bắt đầu của đường cắt: "))
           (setq p2 (getpoint p1 "\nChọn điểm kết thúc của đường cắt: "))
           (setq p3 (getpoint p2 "\nChọn vị trí đặt đường Dim chi tiết: ")))
    (progn
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_BE")
      (setq undo_on T)
      (setvar "OSMODE" 0)

      ;; Line tạm (WCS) để lấy giao điểm
      (entmake (list '(0 . "LINE") (cons 10 (trans p1 1 0)) (cons 11 (trans p2 1 0))))
      (setq tmp (entlast))
      (setq lineobj (vlax-ename->vla-object tmp))

      ;; Các đối tượng cắt qua đường cắt (fence nhận điểm UCS)
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

      ;; Lọc điểm trùng (sai số 0.1)
      (foreach p pts
        (if (not (vl-some '(lambda (x) (< (distance p x) 0.1)) uniq))
          (setq uniq (cons p uniq))
        )
      )
      ;; Sắp xếp dọc đường cắt
      (setq sorted (vl-sort uniq '(lambda (a b) (< (distance p1 a) (distance p1 b)))))

      (if (< (length sorted) 2)
        (princ "\nĐường cắt chỉ đi qua dưới 2 điểm, không đủ để tạo Dim!")
        (progn
          ;; 1. Dim chi tiết
          (setq k 0 s "")
          (while (< k (1- (length sorted)))
            (command "_.DIMALIGNED" (nth k sorted) (nth (1+ k) sorted) p3)
            (setq s (strcat s (rtos (distance (nth k sorted) (nth (1+ k) sorted)) 2 2) "  "))
            (setq k (1+ k))
          )
          ;; 2. Dim tổng, đẩy ra phía xa đường cắt hơn dim chi tiết
          (setq ang1 (angle p1 p2)
                side (- (* (- (car p2) (car p1)) (- (cadr p3) (cadr p1)))
                        (* (- (cadr p2) (cadr p1)) (- (car p3) (car p1))))
                dirang (if (< side 0) (- ang1 (/ pi 2)) (+ ang1 (/ pi 2)))
                sp (* 3.5 (getvar "DIMTXT")
                      (if (> (getvar "DIMSCALE") 0) (getvar "DIMSCALE") 1.0))
                p4 (polar p3 dirang sp))
          (command "_.DIMALIGNED" (car sorted) (last sorted) p4)

          (princ (strcat "\nSố đoạn: " (itoa (1- (length sorted)))
                         " | Tổng: " (rtos (distance (car sorted) (last sorted)) 2 2)))
          (princ (strcat "\nCác đoạn: " s))
        )
      )

      (command "_.UNDO" "_E")
      (setq undo_on nil)
      (setvar "OSMODE" old_os)
      (setvar "CMDECHO" old_echo)
      (princ "\nĐã hoàn thành!")
    )
  )
  (princ)
)
(princ "\n--- Đã tải Lisp Dim Cắt Tại Giao Điểm (v2) ---")
(princ "\n--- Gõ lệnh: DGD để sử dụng ---")
(princ)
