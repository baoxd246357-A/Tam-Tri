;;; compile_to_fas.lsp - bien dich SDOpLat.lsp thanh SDOpLat.fas (chay trong AutoCAD tren may nguoi ban)
;;; Dung: APPLOAD file nay, go BIENDICH, chon SDOpLat.lsp trong thu muc ban hang (build bang --licensed --fas).
;;; Neu bao "bad function: VLISP-COMPILE": go VLIDE (mo trinh soan Visual LISP), quay lai cua so AutoCAD, go BIENDICH lai.
;;; Sau khi co SDOpLat.fas: XOA SDOpLat.lsp khoi goi gui khach (khong co file .lsp thi khach chi nhan ma da bien dich).
(vl-load-com)
(defun c:BIENDICH (/ f out ok)
  (cond
    ((not vlisp-compile)
     ;; ham bien dich chi co sau khi trinh soan Visual LISP (VLIDE) duoc mo trong phien nay
     (princ "\nChua co ham bien dich (VLISP-COMPILE). Dang mo VLIDE... Quay lai cua so AutoCAD roi go BIENDICH lan nua.")
     (command "_.VLIDE"))
    ((setq f (getfiled "Chon SDOpLat.lsp can bien dich" "" "lsp" 4))
     (setq out (strcat (vl-filename-directory f) "\\SDOpLat.fas"))
     ;; che do chuan 'st truoc (on dinh nhat); loi thi thu 'lsa (toi uu + noi)
     (setq ok (vl-catch-all-apply 'vlisp-compile (list 'st f out)))
     (if (or (vl-catch-all-error-p ok) (not ok) (not (findfile out)))
       (setq ok (vl-catch-all-apply 'vlisp-compile (list 'lsa f out))))
     (princ (if (and ok (not (vl-catch-all-error-p ok)) (findfile out))
              (strcat "\nDa tao: " out "\nThu: (load \"" (vl-string-translate "\\" "/" out) "\") roi go SDKICHHOAT.")
              "\nBien dich that bai. Mo VLIDE, nap SDOpLat.lsp (File > Open), roi Tools > Compile File, xem khung Build Output."))))
  (princ))
(princ "\nGo BIENDICH de bien dich SDOpLat.lsp -> SDOpLat.fas")
(princ)
