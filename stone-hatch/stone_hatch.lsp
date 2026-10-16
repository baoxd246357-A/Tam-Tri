;; Lệnh SH_STONE: chọn 1 polyline kín (đúng 2600x1850) -> Superhatch ảnh đá.
;; Sửa đường dẫn ảnh bên dưới. Cần Express Tools. Ảnh DPI 25.4: scale 1 = 1px = 1mm.
(defun c:SH_STONE (/ img pt)
  (setq img (getfiled "Chon anh da" "" "png;jpg" 0))
  (setq pt (getpoint "\nGoc duoi-trai cua tam da: "))
  (command "_.SUPERHATCH" "_Image" img "_Select" pause "" pt 1 0)
  (princ))
