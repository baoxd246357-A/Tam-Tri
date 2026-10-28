;;; ==========================================================================
;;;  Op Lat Tools v1.0.0 - bo cong cu lap shop drawing op lat da / gach cho AutoCAD
;;;  Nap: APPLOAD -> SDOpLat.lsp, roi go SDMENU (menu + toolbar) hoac SDPANEL.
;;;  File sinh tu dong tu ShopDrawing 2.58.0 boi tools/build_oplat.py - khong sua tay.
;;; ==========================================================================
(vl-load-com)
(setq *SD:VER* "1.0.0")

;;; --------------------------------------------------------------------------
;;;  Thiet lap mac dinh (luu kem trong ban ve bang LDATA)
;;; --------------------------------------------------------------------------
(setq *SD:SCALE*    (cond ((vlax-ldata-get "SD" "SCALE")) (*SD:SCALE*) (100)))
(setq *SD:DETSCALE* (cond ((vlax-ldata-get "SD" "DETSCALE")) (*SD:DETSCALE*) (25)))
(or *SD:MARK* (setq *SD:MARK* 1))

;; Danh sach layer: (ten mau linetype lineweight[1/100 mm])
(setq *SD:LAYERS*
  '(("SD-TRUC"      1 "CENTER"     13)
    ("SD-KHUNG"     7 "Continuous" 50)
    ("SD-BANG"      7 "Continuous" 18)
    ("SD-BETONG"    7 "Continuous" 35)
    ("SD-THEP-CHU"  2 "Continuous" 40)
    ("SD-THEP-DAI"  3 "Continuous" 25)
    ("SD-THEP-HINH" 5 "Continuous" 35)
    ("SD-BULONG"    6 "Continuous" 25)
    ("SD-KICHTHUOC" 4 "Continuous" 18)
    ("SD-CHU"       7 "Continuous" 18)
    ("SD-KYHIEU"    6 "Continuous" 25)
    ("SD-KHUAT"     8 "HIDDEN"     18)
    ("SD-HATCH"     8 "Continuous" 13)
    ("SD-GACH"      8 "Continuous" 13)
    ("SD-GACH-CAT" 30 "Continuous" 13)
    ("SD-PAT"       1 "Continuous" 25)
    ("SD-OP-LOP"    7 "Continuous" 25)
    ("SD-GACH-VIEN" 40 "Continuous" 18)
    ("SD-GACH-DOC"   3 "Continuous" 13)
    ("SD-GACH-VAN"   8 "Continuous" 13)
    ("SD-GACH-ANH"   7 "Continuous" 13)
    ("SD-DUONG-CAT"  1 "Continuous" 18)
    ("SD-GACH-NEST"  3 "Continuous" 18)
    ("SD-NEST-TAM"   7 "Continuous" 50)
    ("SD-NEST-LE"    8 "DASHED" 13)
    ("SD-NEST-VIEN"  3 "Continuous" 35)
    ("SD-NEST-VUN"   9 "Continuous" 13)
    ("SD-NEST-TO"    9 "Continuous" 13)
    ("SD-NEST-CHU"   7 "Continuous" 18)
    ("SD-PANEL"      7 "Continuous" 25)
    ("INFILL-TIMBER" 30 "Continuous" 25)
    ("SD-LEN-CHAN" 140 "Continuous" 18)
    ("SD-GIACONG"   7 "Continuous" 35)
    ("SD-CF-VAN"   41 "Continuous" 25)
    ("SD-CF-SUON"   3 "Continuous" 18)
    ("SD-CF-GONG"   5 "Continuous" 25)
    ("SD-CF-TY"     1 "Continuous" 25)
    ("SD-CF-CHONG"  6 "Continuous" 25)
    ("SD-GIAO"    140 "Continuous" 25)
    ("SD-GIANG"     2 "Continuous" 18)
    ("SD-OSAN"      8 "Continuous" 13)))

;;; --------------------------------------------------------------------------
;;;  Ham tien ich chung
;;; --------------------------------------------------------------------------
;; Sap xep KHONG bo phan tu trung khoa (vl-sort bo cac phan tu "bang nhau" theo ham so sanh -> mat ban ghi)
(defun sd:sort (lst f)
  (if lst (mapcar '(lambda (k) (nth k lst)) (vl-sort-i lst f))))

(defun sd:doc () (vla-get-ActiveDocument (vlax-get-acad-object)))
(defun sd:sc () (float *SD:SCALE*))

;; Bat dau / ket thuc lenh: luu bien he thong, undo mark, bat loi
(defun sd:begin ()
  (setq *SD:OLDERR* *error*
        *SD:VARS*   (mapcar '(lambda (v) (cons v (getvar v)))
                            '("CMDECHO" "OSMODE" "CLAYER")))
  (setq *error* sd:error *SD:IMCLIPS* nil)
  (vla-StartUndoMark (sd:doc))
  (setvar "CMDECHO" 0)
  (sd:ensure))

(defun sd:finish ()
  (setq *SD:CKNAME* nil *SD:VKID* nil)
  ;; bang thong ke tu cap nhat (neu co): ve lai khi lenh vua chay lam doi so lieu thep
  (if (and (not *SD:NBRUN*) (vlax-ldata-get "SD" "TKAUTO")) (vl-catch-all-apply 'sd:tk-refresh '(nil)))
  ;; xoa doi tuong tam (offset...) neu con
  (foreach o *SD:TMP* (vl-catch-all-apply 'vla-Delete (list o)))
  (setq *SD:TMP* nil)
  (foreach p *SD:VARS* (vl-catch-all-apply 'setvar (list (car p) (cdr p))))
  (vl-catch-all-apply 'vla-EndUndoMark (list (sd:doc)))
  (setq *error* *SD:OLDERR*)
  (princ))

(defun sd:error (msg)
  (if (not (wcmatch (strcase msg t) "*cancel*,*quit*,*exit*,*break*"))
    (princ (strcat "\n[SD] Loi: " msg)))
  (sd:finish))

;; Toa do: UCS <-> WCS, cong toa do
(defun sd:w (p) (trans p 1 0))
(defun sd:p+ (p dx dy) (list (+ (car p) dx) (+ (cadr p) dy) 0.0))
(defun sd:getpt (msg base / p)
  (if *SD:BPT* ; che do lo (SDNHAPBANG): diem chen dat san, dung 1 lan
    (progn (setq p *SD:BPT* *SD:BPT* nil) p)
    (progn
      (setq p (if base (getpoint (trans base 0 1) msg) (getpoint msg)))
      (if (listp p) (if p (sd:w p))))))

;; Dinh dang so (khong bi anh huong DIMZIN)
(defun sd:rtos (x p / dz r)
  (setq dz (getvar "DIMZIN"))
  (setvar "DIMZIN" 0)
  (setq r (rtos x 2 p))
  (setvar "DIMZIN" dz)
  r)
(defun sd:num (x)
  (if (equal x (fix x) 1e-6)
    (sd:rtos x 0)
    (vl-string-right-trim "." (vl-string-right-trim "0" (sd:rtos x 3)))))

;; Nhap lieu co gia tri mac dinh
(defun sd:getreal (msg def / v)
  (initget 6)
  (setq v (getreal (strcat msg " <" (sd:num def) ">: ")))
  (if v v def))
(defun sd:getint (msg def / v)
  (initget 6)
  (setq v (getint (strcat msg " <" (itoa def) ">: ")))
  (if v v def))
(defun sd:getstr (msg def / v)
  (setq v (getstring t (strcat msg " <" def ">: ")))
  (if (= v "") def v))

;;; --------------------------------------------------------------------------
;;;  HOP THOAI NHAP LIEU (DCL sinh tu dong) - dung chung cho moi lenh
;;;  Truong: (khoa nhan kieu mac-dinh [lua-chon] [dieu-kien])
;;;    kieu : real (> 0), real0 (so bat ky, >= 0 neu can), int (> 0), int0 (>= 0), str, kw (danh sach), tog (Co/Khong), note
;;;    lua-chon (kw): ("Thang" "Sole" ...) hoac (("Thang" . "Lat thang") ...)
;;;    dieu-kien: ("khoa" "gia-tri1" ...) -> truong chi dung khi truong khoa co mot trong cac gia tri
;;;  (sd:dlg tieu-de truong) -> T (OK, gia tri trong *SD:FV*, doc bang sd:v) hoac nil (Huy)
;;;  Tat hop thoai (lenh SDDLG) -> hoi lan luot tren dong lenh voi cung danh sach truong.
;;; --------------------------------------------------------------------------
(defun sd:v (k) (cdr (assoc k *SD:FV*)))
(defun sd:dlg-on () (/= (vlax-ldata-get "SD" "DLG") "Khong"))
(defun sd:kv (c) (if (listp c) (car c) c))
(defun sd:kl (c) (if (listp c) (cdr c) c))
(defun sd:fok (f vals / c)
  (setq c (nth 5 f))
  (or (null c) (member (cdr (assoc (car c) vals)) (cdr c))))
(defun sd:fstr (f v)
  (cond ((member (nth 2 f) '(real real0)) (sd:num v))
        ((member (nth 2 f) '(int int0)) (itoa v))
        ((= (nth 2 f) 'tog) (if v "1" "0"))
        ((= (nth 2 f) 'kw) (itoa (max 0 (cond ((vl-position v (mapcar 'sd:kv (nth 4 f)))) (0)))))
        (t (if v v ""))))

;; Hoi 1 truong tren dong lenh
(defun sd:ask (f / k lb tp d v)
  (setq lb (strcat "\n" (nth 1 f)) tp (nth 2 f) d (nth 3 f))
  (cond
    ((= tp 'real) (sd:getreal lb d))
    ((= tp 'real0) (initget 0) (cond ((getreal (strcat lb " <" (sd:num d) ">: "))) (d)))
    ((= tp 'int) (sd:getint lb d))
    ((= tp 'int0) (initget 4) (cond ((getint (strcat lb " <" (itoa d) ">: "))) (d)))
    ((= tp 'str) (sd:getstr lb d))
    ((= tp 'bar) (sd:getbar lb d))
    ((= tp 'tog) (initget "Co Khong")
                 (= "Co" (cond ((getkword (strcat lb " [Co/Khong] <" (if d "Co" "Khong") ">: ")))
                               ((if d "Co" "Khong")))))
    ((= tp 'kw) (initget (sd:join (mapcar 'sd:kv (nth 4 f)) " "))
                (cond ((getkword (strcat lb " [" (sd:join (mapcar 'sd:kv (nth 4 f)) "/") "] <" d ">: "))) (d)))
    (t (princ lb) nil)))

;; Ghi DCL tam
;; Ghi 1 dong vao file
(defun sd:wl (f s) (write-line s f))

(defun sd:dlg-dcl (title fields / fn f n half i lb)
  (setq fn (vl-filename-mktemp "sdform" nil ".dcl") n (length fields)
        half (if (> n 12) (/ (1+ n) 2) n) i 0)
  (if (setq f (open fn "w"))
    (progn
      (sd:wl f (strcat "sdform : dialog { label = \"" (vl-string-translate "\"" "'" title) "\";"))
      (if *SD:DPIC*
        (sd:wl f ": image { key = \"img\"; width = 50; height = 17; color = 250; fixed_width = true; fixed_height = true; alignment = centered; }"))
      (sd:wl f ": row { : column {")
      (foreach fd fields
        (if (= i half) (sd:wl f "} : column {"))
        (setq lb (vl-string-translate "\"" "'" (nth 1 fd)))
        (cond
          ((= (nth 2 fd) 'note) (sd:wl f (strcat ": text { label = \"" lb "\"; }")))
          ((= (nth 2 fd) 'tog) (sd:wl f (strcat ": toggle { key = \"f" (itoa i) "\"; label = \"" lb "\"; }")))
          ((= (nth 2 fd) 'kw)
           (sd:wl f (strcat ": row { : text { label = \"" lb "\"; width = 36; } : popup_list { key = \"f" (itoa i)
                        "\"; width = 24; } }")))
          (t (sd:wl f (strcat ": row { : text { label = \"" lb "\"; width = 36; } : edit_box { key = \"f" (itoa i)
                          "\"; edit_width = " (if (member (nth 2 fd) '(str bar)) "22" "12") "; } }"))))
        (setq i (1+ i)))
      (sd:wl f "} }")
      (sd:wl f ": text { key = \"err\"; width = 60; }")
      (sd:wl f ": row { : button { key = \"cmdline\"; label = \"Nhap tren dong lenh\"; } ok_cancel; }")
      (sd:wl f "}")
      (close f)
      fn)))

;; Doc gia tri hien tai trong hop thoai -> ((khoa . gia-tri) ...) hoac chuoi loi
(defun sd:dlg-read (/ i vals s v err)
  (setq i 0)
  (foreach f *SD:DF*
    (setq s (get_tile (strcat "f" (itoa i))))
    (setq v (cond
              ((member (nth 2 f) '(real real0))
               (if (setq v (distof s 2)) v (progn (setq err (cond (err) ((strcat "So khong hop le: " (nth 1 f))))) (nth 3 f))))
              ((member (nth 2 f) '(int int0))
               (if (wcmatch s "#*") (atoi s) (progn (setq err (cond (err) ((strcat "So nguyen khong hop le: " (nth 1 f))))) (nth 3 f))))
              ((= (nth 2 f) 'tog) (= s "1"))
              ((= (nth 2 f) 'kw) (sd:kv (nth (atoi s) (nth 4 f))))
              ((= (nth 2 f) 'note) nil)
              ((= (nth 2 f) 'bar)
               (cond ((sd:parse-bar s))
                     (t (setq err (cond (err) ((strcat "Sai dinh dang (vd 3d20): " (nth 1 f))))) (sd:parse-bar (nth 3 f)))))
              (t s)))
    (if (and (sd:fok f vals) (member (nth 2 f) '(real int)) (numberp v) (<= v 0) (not err))
      (setq err (strcat "Phai lon hon 0: " (nth 1 f))))
    (setq vals (append vals (list (cons (car f) v))) i (1+ i)))
  (if err err vals))

;; Bat / tat cac truong theo dieu kien
(defun sd:dlg-modes (/ vals i)
  (setq vals (sd:dlg-read) i 0)
  (if (listp vals)
    (foreach f *SD:DF*
      (if (nth 5 f) (mode_tile (strcat "f" (itoa i)) (if (sd:fok f vals) 0 1)))
      (setq i (1+ i))))
  (if (listp vals) (sd:pic-draw vals)))

(defun sd:dlg (title fields)
  (cond
    ;; SDNHAPBANG lay danh sach truong cua lenh (tao file mau): khong hien hop thoai, lenh dung lai
    ((= *SD:BATCH* 'SCHEMA) (setq *SD:BATCH* nil *SD:SCHEMA* (list title fields)) nil)
    ;; che do lo: gia tri lay tu dong bang (o trong = mac dinh)
    (*SD:BATCH* (setq *SD:DF* fields *SD:FV* (sd:nb-fv fields *SD:BATCH*) *SD:BATCH* nil) t)
    (t (sd:dlg-ui title fields))))

(defun sd:dlg-ui (title fields / fn id res i vals)
  (setq *SD:DF* fields *SD:FV* nil res nil *SD:DPIC* (sd:pic-for title))
  (if (and (sd:dlg-on) (setq fn (sd:dlg-dcl title fields))
           (setq id (load_dialog fn)) (> id 0) (new_dialog "sdform" id))
    (progn
      (setq i 0)
      (foreach f fields
        (if (= (nth 2 f) 'kw)
          (progn (start_list (strcat "f" (itoa i))) (mapcar 'add_list (mapcar 'sd:kl (nth 4 f))) (end_list)))
        (if (/= (nth 2 f) 'note) (set_tile (strcat "f" (itoa i)) (sd:fstr f (nth 3 f))))
        (if (/= (nth 2 f) 'note) (action_tile (strcat "f" (itoa i)) "(sd:dlg-modes)"))
        (setq i (1+ i)))
      (sd:dlg-modes)
      (action_tile "accept" "(sd:dlg-ok)")
      (action_tile "cmdline" "(done_dialog 2)")
      (setq res (start_dialog))
      (unload_dialog id)
      (vl-file-delete fn)))
  (setq *SD:DPIC* nil)
  (cond
    ((= res 1) t)
    ((= res 0) (princ "\n[SD] Da huy.") nil)
    (t ; tat hop thoai / DCL loi / chon "Nhap tren dong lenh"
     (foreach f fields
       (setq vals (append vals (list (cons (car f) (if (sd:fok f vals) (sd:ask f) (nth 3 f)))))))
     (setq *SD:FV* vals)
     t)))

;;; SDDLG - bat / tat hop thoai nhap lieu
(defun c:SDDLG (/ v)
  (initget "Co Khong")
  (setq v (cond ((getkword (strcat "\nDung hop thoai nhap lieu [Co/Khong] <" (if (sd:dlg-on) "Co" "Khong") ">: ")))
                ((if (sd:dlg-on) "Co" "Khong"))))
  (vlax-ldata-put "SD" "DLG" v)
  (princ (strcat "\n[SD] Hop thoai nhap lieu: " (if (= v "Co") "BAT" "TAT (hoi tren dong lenh)") "."))
  (princ))

;;; --------------------------------------------------------------------------
;;;  HINH MINH HOA TRONG HOP THOAI (image tile, ve vector khi chay)
;;;  Toa do thiet ke: khung 100 x 75, goc trai duoi. Nguyen to:
;;;   ("L" x1 y1 x2 y2 mau)   ("P" mau kin? (x y x y ...))   ("C" x y r mau)   ("D" x y r mau) cham dac
;;;   ("T" x y "CHU" cao mau can-le)   ("H" x1 x2 y "nhan" mau) kich thuoc ngang
;;;   ("V" x y1 y2 "nhan" mau ["L"]) kich thuoc dung (chu ben phai, "L" = ben trai)
;;; --------------------------------------------------------------------------
;; Font net 4 x 6
(setq *SD:FONT*
  '(("A" (0 0 0 4 2 6 4 4 4 0) (0 3 4 3)) ("B" (0 0 0 6 3 6 4 5 3 3 0 3) (3 3 4 2 4 1 3 0 0 0))
    ("C" (4 1 3 0 1 0 0 1 0 5 1 6 3 6 4 5)) ("D" (0 0 0 6 3 6 4 5 4 1 3 0 0 0))
    ("E" (4 0 0 0 0 6 4 6) (0 3 3 3)) ("F" (0 0 0 6 4 6) (0 3 3 3))
    ("G" (4 5 3 6 1 6 0 5 0 1 1 0 3 0 4 1 4 3 2 3)) ("H" (0 0 0 6) (4 0 4 6) (0 3 4 3))
    ("I" (1 0 3 0) (2 0 2 6) (1 6 3 6)) ("J" (0 1 1 0 3 0 4 1 4 6)) ("K" (0 0 0 6) (4 6 0 2) (1 3 4 0))
    ("L" (0 6 0 0 4 0)) ("M" (0 0 0 6 2 3 4 6 4 0)) ("N" (0 0 0 6 4 0 4 6))
    ("O" (1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0)) ("P" (0 0 0 6 3 6 4 5 4 4 3 3 0 3))
    ("Q" (1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0) (2 2 4 0)) ("R" (0 0 0 6 3 6 4 5 4 4 3 3 0 3) (2 3 4 0))
    ("S" (4 5 3 6 1 6 0 5 0 4 1 3 3 3 4 2 4 1 3 0 1 0 0 1)) ("T" (0 6 4 6) (2 6 2 0))
    ("U" (0 6 0 1 1 0 3 0 4 1 4 6)) ("V" (0 6 2 0 4 6)) ("W" (0 6 1 0 2 3 3 0 4 6))
    ("X" (0 0 4 6) (0 6 4 0)) ("Y" (0 6 2 3 4 6) (2 3 2 0)) ("Z" (0 6 4 6 0 0 4 0))
    ("0" (1 0 0 1 0 5 1 6 3 6 4 5 4 1 3 0 1 0)) ("1" (1 5 2 6 2 0) (1 0 3 0))
    ("2" (0 5 1 6 3 6 4 5 4 4 0 0 4 0)) ("3" (0 5 1 6 3 6 4 5 4 4 3 3 4 2 4 1 3 0 1 0 0 1) (1 3 3 3))
    ("4" (3 0 3 6 0 2 4 2)) ("5" (4 6 0 6 0 3 3 3 4 2 4 1 3 0 0 0))
    ("6" (4 5 3 6 1 6 0 5 0 1 1 0 3 0 4 1 4 2 3 3 0 3)) ("7" (0 6 4 6 1 0))
    ("8" (1 3 0 4 0 5 1 6 3 6 4 5 4 4 3 3 1 3 0 2 0 1 1 0 3 0 4 1 4 2 3 3))
    ("9" (0 1 1 0 3 0 4 1 4 5 3 6 1 6 0 5 0 4 1 3 4 3))
    ("-" (1 3 3 3)) ("=" (1 2 3 2) (1 4 3 4)) ("/" (0 0 4 6)) ("." (2 0 2 1)) ("+" (2 1 2 5) (0 3 4 3))
    ("(" (3 6 2 5 2 1 3 0)) (")" (1 6 2 5 2 1 1 0)) (":" (2 1 2 2) (2 4 2 5)) ("@" (4 1 3 0 1 0 0 1 0 5 1 6 3 6 4 5 4 2 2 2 2 4 4 4))))

(defun sd:pv (v k) (cdr (assoc k v)))
(defun sd:pnum (v k def / x) (setq x (sd:pv v k)) (if (numberp x) x def))

;; Doi nguyen to -> danh sach doan thang (x1 y1 x2 y2 mau) trong toa do thiet ke
(defun sd:pic-segs (prims / r e x y s h c w k g pts i a)
  (foreach e prims
    (cond
      ((= (car e) "L") (setq r (cons (cdr e) r)))
      ((= (car e) "P")
       (setq pts (nth 3 e) c (cadr e))
       (if (caddr e) (setq pts (append pts (list (car pts) (cadr pts)))))
       (while (cdddr pts)
         (setq r (cons (list (car pts) (cadr pts) (caddr pts) (cadddr pts) c) r) pts (cddr pts))))
      ((member (car e) '("C" "D"))
       (foreach rr (if (= (car e) "D") (list (nth 3 e) (* 0.66 (nth 3 e)) (* 0.33 (nth 3 e))) (list (nth 3 e)))
         (setq i 0)
         (repeat 12
           (setq a (* i (/ pi 6)))
           (setq r (cons (list (+ (nth 1 e) (* rr (cos a))) (+ (nth 2 e) (* rr (sin a)))
                               (+ (nth 1 e) (* rr (cos (+ a (/ pi 6))))) (+ (nth 2 e) (* rr (sin (+ a (/ pi 6)))))
                               (nth 4 e))
                         r)
                 i (1+ i)))))
      ((= (car e) "T")
       (setq s (strcase (nth 3 e)) h (nth 4 e) c (nth 5 e) k (/ h 6.0) w (* k (- (* 5 (strlen s)) 1))
             x (cond ((= (nth 6 e) "C") (- (nth 1 e) (/ w 2))) ((= (nth 6 e) "R") (- (nth 1 e) w)) (t (nth 1 e)))
             y (- (nth 2 e) (/ h 2.0)) i 0)
       (repeat (strlen s)
         (foreach st (cdr (assoc (substr s (1+ i) 1) *SD:FONT*))
           (setq g st)
           (while (cddr g)
             (setq r (cons (list (+ x (* k (+ (* 5 i) (car g)))) (+ y (* k (cadr g)))
                                 (+ x (* k (+ (* 5 i) (caddr g)))) (+ y (* k (cadddr g))) c)
                           r)
                   g (cddr g))))
         (setq i (1+ i))))
      ((= (car e) "H")
       (setq x (nth 1 e) w (nth 2 e) y (nth 3 e) c (nth 5 e))
       (setq r (append (list (list x y w y c) (list x (- y 1.5) x (+ y 1.5) c) (list w (- y 1.5) w (+ y 1.5) c)) r)
             r (append (sd:pic-segs (list (list "T" (/ (+ x w) 2.0) (if (> y 68) (- y 3.5) (+ y 3.5)) (nth 4 e) 4.0 c "C"))) r)))
      ((= (car e) "V")
       (setq x (nth 1 e) y (nth 2 e) w (nth 3 e) c (nth 5 e))
       (setq r (append (list (list x y x w c) (list (- x 1.5) y (+ x 1.5) y c) (list (- x 1.5) w (+ x 1.5) w c)) r)
             r (append (sd:pic-segs (list (if (= (nth 6 e) "L")
                                              (list "T" (- x 2.0) (/ (+ y w) 2.0) (nth 4 e) 4.0 c "R")
                                              (list "T" (+ x 2.0) (/ (+ y w) 2.0) (nth 4 e) 4.0 c "L")))) r)))))
  r)

;; Ve len image tile "img"
(defun sd:pic-draw (vals / prims segs w h k ox oy)
  (if (and *SD:DPIC* (setq prims (vl-catch-all-apply *SD:DPIC* (list vals))) (listp prims)
           (setq segs (vl-catch-all-apply 'sd:pic-segs (list prims))) (listp segs))
    (progn
      (setq w (dimx_tile "img") h (dimy_tile "img") k (min (/ w 100.0) (/ h 75.0))
            ox (/ (- w (* 100 k)) 2.0) oy (/ (- h (* 75 k)) 2.0))
      (start_image "img")
      (fill_image 0 0 w h 250)
      (foreach s segs
        (vector_image (fix (+ ox (* k (nth 0 s)))) (fix (+ oy (* k (- 75 (nth 1 s)))))
                      (fix (+ ox (* k (nth 2 s)))) (fix (+ oy (* k (- 75 (nth 3 s))))) (nth 4 s)))
      (end_image))))
(defun sd:rectp (x y w h c) (list "P" c t (list x y (+ x w) y (+ x w) (+ y h) x (+ y h))))

(defun sd:pic-gach (v / pat W H a l sz tiles e ok)
  (setq pat (cond ((sd:pv v "pat")) ("Thang")) W (sd:pnum v "W" 600) H (sd:pnum v "H" 600))
  (if (and (member pat '("Xuongca" "Chevron")) (< (abs (- W H)) 1)) (setq W (* 3 H)))
  (setq a (max 0.25 (min 4.0 (/ W H))) sz 9.0
        tiles (cond ((= pat "Xuongca") (sd:gen-herring 0 100 0 75 (* sz (max a (/ 1 a))) sz 1.0))
                    ((= pat "Chevron") (sd:gen-chevron 0 100 0 75 (* sz (max a (/ 1 a))) sz 1.0 (* pi (/ (max 20.0 (min 65.0 (sd:pnum v "cva" 45.0))) 180.0))))
                    (t (sd:gen-grid 0 100 0 75 (* sz a) sz 1.0 "Goc" (if (= pat "Sole") (sd:pnum v "off" 0.5) 0.0)))))
  (foreach tl tiles
    (setq e (mapcar '(lambda (p) (list (+ 8 (* 0.84 (car p))) (+ 6 (* 0.84 (cadr p))))) (car tl))
          ok (vl-every '(lambda (p) (and (<= 8 (car p) 92) (<= 6 (cadr p) 69))) e))
    (if ok (setq l (cons (list "P" 30 t (apply 'append e)) l))))
  (setq l (cons (sd:rectp 8 6 84 63 7) l))
  (if (sd:pv v "bord") (setq l (cons (sd:rectp 4 2 92 71 40) l)))
  l)

(defun sd:pic-len (v / l x)
  (setq l (list (list "L" 14 15 95 15 7) (list "L" 14 70 14 15 7) (list "T" 34 45 "TUONG" 5 8 "C")
                (sd:rectp 55 15 14 40 8) (list "T" 62 35 "CUA" 4 8 "C")) x 14)
  (while (< x 54) (setq l (cons (sd:rectp x 15 (min 15 (- 54 x)) 7 30) l) x (+ x 16)))
  (setq x 70)
  (while (< x 95) (setq l (cons (sd:rectp x 15 (min 15 (- 95 x)) 7 30) l) x (+ x 16)))
  (append l (list (list "H" 14 29 9 "LC" 4) (list "V" 10 15 22 "HC" 4 "L"))))

(defun sd:pic-lop (v / lays n tot y l i th)
  (setq lays (sd:parse-layers (cond ((sd:pv v "lop")) (""))) n (length lays)
        tot (apply '+ (cons 0.0 (mapcar 'cadr lays))) i 0)
  (if (= n 0) (setq lays '(("1" 20.0) ("2" 30.0) ("3" 150.0)) n 3 tot 200.0))
  (if (= (sd:pv v "ori") "Tuong")
    (progn (setq y 20)
      (foreach ly lays
        (setq th (max 5.0 (* 45.0 (/ (cadr ly) tot))) l (cons (sd:rectp y 8 th 60 (nth (rem i 4) '(30 7 3 8))) l)
              l (cons (list "T" (+ y (/ th 2)) 72 (itoa (1+ i)) 4 7 "C") l) y (+ y th) i (1+ i))))
    (progn (setq y 65)
      (foreach ly lays
        (setq th (max 5.0 (* 45.0 (/ (cadr ly) tot))) l (cons (sd:rectp 10 (- y th) 70 th (nth (rem i 4) '(30 7 3 8))) l)
              l (cons (list "T" 88 (- y (/ th 2)) (itoa (1+ i)) 4 7 "C") l) y (- y th) i (1+ i)))))
  l)

(defun sd:pic-datho (v)
  (list (sd:rectp 5 5 90 65 7) (sd:rectp 9 9 82 57 8)
        (sd:rectp 10 10 25 25 30) (sd:rectp 36 10 25 25 30) (sd:rectp 62 10 25 25 30) (sd:rectp 10 36 25 12 30)
        (sd:rectp 36 36 25 12 30) (sd:rectp 62 36 12 28 30)
        (list "H" 5 95 2 "SL" 4) (list "V" 97 5 70 "SB" 4) (list "T" 45 58 "XEN BIEN" 3.5 8 "C")))

(defun sd:pic-giacong (v)
  (list (sd:rectp 5 5 90 65 8) (list "T" 8 64 "G1-C3" 4 7 "L")
        (list "P" 30 t '(25 15 75 15 75 40 55 50 25 50)) (list "H" 25 75 9 "W" 4) (list "V" 18 15 50 "H" 4)
        (list "T" 70 50 "CANH XIEN" 3 4 "L")))

(defun sd:pic-set (v / sc ds)
  (setq sc (itoa (fix (sd:pnum v "sc" 100))) ds (itoa (fix (sd:pnum v "ds" 25))))
  (list (sd:rectp 4 6 56 60 8) (sd:rectp 10 18 38 38 7) (list "L" 10 37 48 37 7) (list "L" 29 18 29 56 7)
        (list "H" 10 48 60 "3800" 4) (list "T" 32 11 (strcat "MAT BANG 1/" sc) 3.5 7 "C")
        (list "C" 48 37 6 2) (list "L" 54 37 66 42 2)
        (list "C" 82 42 15 2) (sd:rectp 72 36 20 12 7) (list "L" 72 42 92 42 4)
        (list "T" 82 22 (strcat "CHI TIET 1/" ds) 3.5 7 "C")
        (list "T" 82 15 "LAYER DIM TEXT" 2.5 8 "C")))

(defun sd:pic-gachtk (v / l x y)
  (setq y 50)
  (repeat 3
    (setq x 6)
    (repeat 4 (setq l (cons (sd:rectp x y 9 9 (if (< x 30) 30 7)) l) x (+ x 10)))
    (setq y (- y 10)))
  (setq l (append l (list (sd:rectp 6 20 40 40 7) (list "T" 26 14 "VIEN CAT" 3.5 1 "C")
                          (list "T" 26 66 (strcat "HAO HUT " (sd:num (sd:pnum v "loss" 3)) "/100") 3.5 2 "C"))))
  (foreach r '(55 47 39 31 23)
    (setq l (cons (list "L" 54 r 96 r 8) l)))
  (append l (list (sd:rectp 54 15 42 48 7) (list "L" 64 15 64 63 8) (list "L" 80 15 80 63 8)
                  (list "T" 59 59 "MA" 3 4 "C") (list "T" 72 59 "SL" 3 4 "C") (list "T" 88 59 "M2" 3 4 "C")
                  (list "T" 59 51 "G1" 3 7 "C") (list "T" 72 51 "124" 3 7 "C") (list "T" 88 51 "44.6" 3 7 "C")
                  (list "T" 59 43 "G1" 3 1 "C") (list "T" 72 43 "18" 3 1 "C")
                  (list "T" 75 8 (strcat "MACH CAT " (sd:num (sd:pnum v "kerf" 3))) 3.5 4 "C"))))

(defun sd:pic-khoda (v / op l)
  (setq op (sd:pv v "op")
        l (list (list "P" 8 t '(14 10 70 10 74 14 18 14)) (sd:rectp 10 14 60 36 30) (sd:rectp 14 18 60 36 30)
                (sd:rectp 18 22 60 36 7) (list "T" 48 46 (cond ((= (type (sd:pv v "id")) 'STR) (sd:pv v "id")) ("T01")) 5 7 "C")
                (list "H" 18 78 64 (sd:num (sd:pnum v "L" 2700)) 4) (list "V" 82 22 58 (sd:num (sd:pnum v "B" 1800)) 4)
                (list "T" 48 32 (strcat "SL " (itoa (fix (sd:pnum v "n" 3)))) 4 2 "C")))
  (cond
    ((= op "Them") (append l (list (list "L" 4 64 14 64 3) (list "L" 9 59 9 69 3))))
    ((= op "Xoa") (append l (list (list "L" 20 24 76 56 1) (list "L" 20 56 76 24 1))))
    ((member op '("Nhap" "Xuat"))
     (append l (list (sd:rectp 84 4 14 16 7) (list "T" 91 12 "CSV" 3 7 "C")
                     (if (= op "Nhap") (list "P" 4 nil '(84 12 74 12 77 14 74 12 77 10)) (list "P" 4 nil '(74 12 84 12 81 14 84 12 81 10))))))
    ((sd:pv v "mode") (append l (list (sd:rectp 84 4 14 16 7) (list "T" 91 12 "CSV" 3 7 "C"))))
    (t l)))

(defun sd:pic-raitam (v / l x y)
  (setq l (list (sd:rectp 10 10 80 48 7) (list "T" 50 66 "RAI TAM" 3.5 7 "C")))
  (foreach x '(10 28 46 64)
    (foreach y '(10 34) (setq l (cons (sd:rectp x y 18 24 3) l))))
  (setq l (cons (sd:rectp 82 10 8 24 4) (cons (sd:rectp 82 34 8 24 30) (cons (list "L" 82 34 90 58 1) (cons (list "L" 82 58 90 34 1) l)))))
  (append l (list (list "T" 50 4 "TAM LON / TAM BU / GO" 2.4 2 "C"))))

;; Hinh theo ma lenh trong tieu de hop thoai
(setq *SD:PICS*
  (list (cons "SDGACH" 'sd:pic-gach) (cons "SDCHANTUONG" 'sd:pic-len) (cons "SDLOP" 'sd:pic-lop)
        (cons "SDDATHO" 'sd:pic-datho) (cons "SDGIACONG" 'sd:pic-giacong)
        (cons "SDSET" 'sd:pic-set) (cons "SDGACHTK" 'sd:pic-gachtk)
        (cons "SDKHODA" 'sd:pic-khoda) (cons "SDRAITAM" 'sd:pic-raitam) (cons "SDVANDA" 'sd:pic-raitam) (cons "SDANHDA" 'sd:pic-raitam) (cons "SDTKDA" 'sd:pic-gachtk) ))

(defun sd:pic-for (title / p)
  (if (and (setq p (vl-string-position (ascii "(") title nil t)) (wcmatch title "*)"))
    (cdr (assoc (substr title (+ p 2) (- (strlen title) p 2)) *SD:PICS*))))

;; Tach chuoi
(defun sd:split (s d / p r)
  (while (setq p (vl-string-search d s))
    (setq r (cons (substr s 1 p) r)
          s (substr s (+ p 1 (strlen d)))))
  (reverse (cons s r)))
(defun sd:join (lst d / r)
  (setq r (car lst))
  (foreach s (cdr lst) (setq r (strcat r d s)))
  r)

;; Cong don: (a b c) -> (0 a a+b a+b+c)
(defun sd:cumul (lst / s r)
  (setq s 0.0 r (list 0.0))
  (foreach d lst (setq s (+ s d) r (cons s r)))
  (reverse r))

;; "3d20" / "3D20" / "3-20" / "3%%c20" -> (3 20.0)
(defun sd:parse-bar (s / i n d)
  (setq s (strcase s) i 1)
  (while (and (<= i (strlen s)) (wcmatch (substr s i 1) "#")) (setq i (1+ i)))
  (setq n (atoi (substr s 1 (1- i))))
  (while (and (<= i (strlen s)) (not (wcmatch (substr s i 1) "#"))) (setq i (1+ i)))
  (setq d (atof (substr s i)))
  (if (and (> n 0) (> d 0.0)) (list n d)))

(defun sd:getbar (msg def / r)
  (while (not (setq r (sd:parse-bar (sd:getstr msg def))))
    (princ "\nSai dinh dang. Vi du: 3d20"))
  r)

;;; --------------------------------------------------------------------------
;;;  Layer, text style, dimstyle
;;; --------------------------------------------------------------------------
(defun sd:ltype (lt)
  (if (not (tblsearch "LTYPE" lt))
    (vl-catch-all-apply 'vla-Load
      (list (vla-get-Linetypes (sd:doc)) lt
            (if (= (getvar "MEASUREMENT") 1) "acadiso.lin" "acad.lin"))))
  (if (tblsearch "LTYPE" lt) lt "Continuous"))

(defun sd:make-layer (name col lt lw)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)
                   (cons 62 col) (cons 6 (sd:ltype lt)) (cons 370 lw))))
  name)

(defun sd:tstyle ()
  (if (not (tblsearch "STYLE" "SD-TEXT"))
    (entmake '((0 . "STYLE") (100 . "AcDbSymbolTableRecord")
               (100 . "AcDbTextStyleTableRecord") (2 . "SD-TEXT") (70 . 0)
               (40 . 0.0) (41 . 1.0) (50 . 0.0) (71 . 0) (42 . 2.5)
               (3 . "arial.ttf") (4 . ""))))
  (if (tblsearch "STYLE" "SD-TEXT") "SD-TEXT" "Standard"))

(defun sd:ensure ()
  (foreach l *SD:LAYERS* (apply 'sd:make-layer l))
  (sd:tstyle)
  (regapp "SD_REBAR")
  (regapp "SD_KL")
  (regapp "SD_CK")
  (regapp "SD_VK")
  (regapp "SD_SAN")
  (regapp "SD_NOI")
  (regapp "SD_TILE")
  (regapp "SD_ANH")
  (regapp "SD_MAVIEN")
  t)

;; Tao / kich hoat dimstyle "SD-1-<ty le>"
(defun sd:use-dimstyle (sc / name)
  (setq sc (fix sc) name (strcat "SD-1-" (itoa sc)))
  (if (tblsearch "DIMSTYLE" name)
    (if (/= (strcase (getvar "DIMSTYLE")) (strcase name))
      (command "_.-DIMSTYLE" "_R" name))
    (progn
      (foreach p (list (cons "DIMSCALE" (float sc))
                       '("DIMTXT" . 2.5) '("DIMASZ" . 1.2) '("DIMEXO" . 1.5)
                       '("DIMEXE" . 1.5) '("DIMDLE" . 1.0) '("DIMGAP" . 0.8)
                       '("DIMCEN" . 0.0)
                       '("DIMTAD" . 1) '("DIMJUST" . 0) '("DIMTIH" . 0)
                       '("DIMTOH" . 0) '("DIMDEC" . 0) '("DIMLUNIT" . 2)
                       '("DIMZIN" . 8) '("DIMATFIT" . 3) '("DIMTMOVE" . 2))
        (setvar (car p) (cdr p)))
      (setvar "DIMTXSTY" (sd:tstyle))
      (setvar "DIMBLK" "_ARCHTICK")
      (command "_.-DIMSTYLE" "_S" name)))
  name)

;;; --------------------------------------------------------------------------
;;;  Tao doi tuong (entmake, toa do WCS)
;;; --------------------------------------------------------------------------
(defun sd:line (p1 p2 lay)
  (entmake (list '(0 . "LINE") (cons 8 lay) (cons 10 p1) (cons 11 p2))))

(defun sd:circle (c r lay)
  (entmake (list '(0 . "CIRCLE") (cons 8 lay) (cons 10 c) (cons 40 r))))

(defun sd:clean-pts (pts closed / r p)
  ;; bo diem hong (nil / khong phai so), diem trung lien tiep va diem dong trung diem dau
  (foreach p pts
    (if (and (listp p) (numberp (car p)) (numberp (cadr p))
             (not (and r (< (distance (list (car p) (cadr p) 0.0) (list (car (car r)) (cadr (car r)) 0.0)) 1e-6))))
      (setq r (cons (list (car p) (cadr p)) r))))
  (setq r (reverse r))
  (if (and closed (cdr r) (< (distance (list (car (car r)) (cadr (car r)) 0.0) (list (car (last r)) (cadr (last r)) 0.0)) 1e-6))
    (setq r (reverse (cdr (reverse r)))))
  r)

(defun sd:plinew (pts closed w lay / q)
  (setq q (sd:clean-pts pts closed))
  (cond
    ((< (length q) (if closed 3 2))
     (princ "\n[SD] Bo qua polyline suy bien (it hon 2-3 dinh sau khi loai diem trung).") nil)
    ((entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                            '(100 . "AcDbPolyline") (cons 90 (length q))
                            (cons 70 (if closed 1 0)) (cons 43 w))
                      (mapcar '(lambda (p) (list 10 (car p) (cadr p))) q))))
    (t (princ "\n[SD] Khong tao duoc polyline (entmake loi).") nil)))
;; Polyline vien/tam kem du lieu mo rong xd; tra nil neu hinh suy bien
(defun sd:mk-tile-poly (lay cs xd / q)
  (setq q (sd:clean-pts cs t))
  (if (>= (length q) 3)
    (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                           '(100 . "AcDbPolyline") (cons 90 (length q)) '(70 . 1))
                     (mapcar '(lambda (p) (list 10 (car p) (cadr p))) q)
                     (list xd)))
    (progn (princ "\n[SD] Bo qua vien suy bien (dien tich bang 0).") nil)))
(defun sd:pline (pts closed lay) (sd:plinew pts closed 0.0 lay))

(defun sd:rect (o w h lay)
  (sd:pline (list o (sd:p+ o w 0) (sd:p+ o w h) (sd:p+ o 0 h)) t lay))

;; Cham tron dac (thanh thep) duong kinh d
(defun sd:dot (c d lay / r)
  (setq r (/ d 4.0))
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                 '(100 . "AcDbPolyline") '(90 . 2) '(70 . 1) (cons 43 (/ d 2.0))
                 (list 10 (- (car c) r) (cadr c)) '(42 . 1.0)
                 (list 10 (+ (car c) r) (cadr c)) '(42 . 1.0))))

;; Text: j = L C R ML MC MR TL TC TR
(defun sd:text (pt str h j lay / h72 v73)
  (setq h72 (cond ((wcmatch j "*C") 1) ((wcmatch j "*R") 2) (t 0))
        v73 (cond ((wcmatch j "M?") 2) ((wcmatch j "T?") 3) (t 0)))
  (entmake (list '(0 . "TEXT") (cons 8 lay) (cons 7 (sd:tstyle)) (cons 10 pt)
                 (cons 11 pt) (cons 40 h) (cons 1 str) (cons 72 h72) (cons 73 v73))))

;; Kich thuoc thang: dir "H" ngang / "V" dung; pd = vi tri duong kich thuoc
(defun sd:dim (p1 p2 dir pd / os cl)
  (if (> (abs (if (= dir "V") (- (cadr p2) (cadr p1)) (- (car p2) (car p1)))) 1e-6)
    (progn
      (setq os (getvar "OSMODE") cl (getvar "CLAYER"))
      (setvar "OSMODE" 0)
      (setvar "CLAYER" "SD-KICHTHUOC")
      (command "_.DIMLINEAR" (trans p1 0 1) (trans p2 0 1)
               (if (= dir "V") "_V" "_H") (trans pd 0 1))
      (setvar "CLAYER" cl)
      (setvar "OSMODE" os))))

(defun sd:dimchain (pts dir pd)
  (while (cadr pts)
    (sd:dim (car pts) (cadr pts) dir pd)
    (setq pts (cdr pts))))

;;; --------------------------------------------------------------------------
;;;  SDSET - Thiet lap ty le, layer, text style, dimstyle
;;; --------------------------------------------------------------------------
(defun c:SDSET (/ sc)
  (sd:begin)
  (if (not (sd:dlg "Thiet lap ban ve (SDSET)"
                   (list (list "sc" "Ty le ban ve chinh 1/" 'int *SD:SCALE*)
                         (list "ds" "Ty le chi tiet (mat cat, ban ma...) 1/" 'int *SD:DETSCALE*))))
    (exit))
  (setq sc (sd:v "sc"))
  (setq *SD:SCALE* sc)
  (setq *SD:DETSCALE* (sd:v "ds"))
  (vlax-ldata-put "SD" "SCALE" *SD:SCALE*)
  (vlax-ldata-put "SD" "DETSCALE" *SD:DETSCALE*)
  (sd:use-dimstyle *SD:DETSCALE*)
  (sd:use-dimstyle sc)
  (setvar "LTSCALE" (* sc 0.25))
  (princ (strcat "\n[SD] Da thiet lap: ty le 1/" (itoa sc)
                 ", chi tiet 1/" (itoa *SD:DETSCALE*)
                 ", layer SD-*, text style SD-TEXT, dimstyle SD-1-" (itoa sc) "."))
  (sd:finish))

(defun sd:bubble (c r lab)
  (sd:circle c r "SD-KYHIEU")
  (sd:text c lab (* 0.9 r) "MC" "SD-CHU"))

(defun sd:cfg (key def) (cond ((vlax-ldata-get "SD" key)) (def)))
(defun sd:cfg-put (key v) (vlax-ldata-put "SD" key v) v)

(defun sd:lapinfo (/ k)
  (setq k (sd:cfg "LAPK" 0.0))
  (if (> k 0)
    (strcat (sd:num k) "d")
    (strcat "TCVN 5574:2018, " (sd:cfg "BETONG" "B25") ", " (sd:cfg "THEP" "CB400-V")
            ", vung " (if (= (sd:cfg "VUNG" "Keo") "Nen") "nen" "keo"))))

;; Gom phan tu trung: (a a b) -> ((a . 2) (b . 1)), giu thu tu
(defun sd:group (lst / r e)
  (foreach x lst
    (if (setq e (assoc x r))
      (setq r (subst (cons x (1+ (cdr e))) e r))
      (setq r (cons (cons x 1) r))))
  (reverse r))
(defun sd:str->nums (s) (if s (mapcar 'atof (vl-remove "" (sd:split s ",")))))
(defun sd:repeat (x n / r) (repeat n (setq r (cons x r))) r)
(defun sd:replace-nth (i v lst / j)
  (setq j -1)
  (mapcar '(lambda (x) (if (= (setq j (1+ j)) i) v x)) lst))

;;; --------------------------------------------------------------------------
;;;  HINH DANG THANH THEP
;;;  (ma  ten  tham-so  diem-ve[0..1]  doan-phu  nhan(tham-so x y can-le)  goi-y  mac-dinh)
;;; --------------------------------------------------------------------------
(setq *SD:SHAPES*
  '(("Thang" "Th\\U+1EB3ng" ("A") ((0 0.35) (1 0.35)) nil
     ((0 0.5 0.75 "MC"))
     "A = chieu dai thanh" (6000.0))
    ("L" "Ch\\U+1EEF L" ("A" "B") ((0 1) (0 0) (1 0)) nil
     ((0 0.55 0.3 "MC") (1 0.05 0.65 "ML"))
     "A = doan ngang, B = doan uon (kich thuoc ngoai)" (3000.0 300.0))
    ("U" "Ch\\U+1EEF U" ("A" "B" "C") ((0 1) (0 0) (1 0) (1 1)) nil
     ((0 0.05 0.65 "ML") (1 0.5 0.3 "MC") (2 0.95 0.65 "MR"))
     "A = canh trai, B = day, C = canh phai" (300.0 3000.0 300.0))
    ("Z" "C\\U+1ED5 d\\U+00EA" ("A" "B" "C") ((0 0) (0.3 0) (0.6 1) (1 1)) nil
     ((0 0.15 0.3 "MC") (1 0.47 0.45 "ML") (2 0.8 0.7 "MC"))
     "A = doan duoi, B = doan xien, C = doan tren" (1000.0 500.0 1000.0))
    ("Dai" "\\U+0110ai k\\U+00EDn" ("A" "B") ((0.3 0) (0.7 0) (0.7 1) (0.3 1) (0.3 0))
     (((0.3 0.85) (0.4 0.55)) ((0.36 1) (0.46 0.7)))
     ((0 0.5 0.3 "MC") (1 0.74 0.5 "ML"))
     "A = be rong, B = chieu cao (kich thuoc ngoai dai), cong them 2 moc 135 do" (170.0 450.0))
    ("Mot" "\\U+0110ai 1 nh\\U+00E1nh" ("A") ((0 0.6) (1 0.6))
     (((0 0.6) (0.08 0.15)) ((1 0.6) (0.92 0.15)))
     ((0 0.5 0.85 "MC"))
     "A = chieu dai thang, cong them 2 moc 135 do" (200.0))))

;; Ve so do hinh dang vao vung chu nhat goc o, rong w, cao h (khong theo ty le)
(defun sd:nmap (p o w h) (sd:p+ o (* w (car p)) (* h (cadr p))))
(defun sd:draw-shape (code prm o w h sc / sh)
  (if (setq sh (assoc code *SD:SHAPES*))
    (progn
      (sd:pline (mapcar '(lambda (p) (sd:nmap p o w h)) (nth 3 sh)) nil "SD-THEP-CHU")
      (foreach s (nth 4 sh)
        (sd:line (sd:nmap (car s) o w h) (sd:nmap (cadr s) o w h) "SD-THEP-CHU"))
      (foreach l (nth 5 sh)
        (if (nth (car l) prm)
          (sd:text (sd:nmap (cdr l) o w h) (sd:num (nth (car l) prm)) (* 1.8 sc) (nth 3 l) "SD-CHU"))))))

;;; --------------------------------------------------------------------------
;;;  Doc du lieu thep tu ban ve
;;;  ban ghi: (so-hieu SL/CK d L soCK hinh-dang (kich-thuoc) (doan-cat))
;;; --------------------------------------------------------------------------
(defun sd:mk< (a b)
  (if (and (wcmatch a "#*") (wcmatch b "#*") (/= (atoi a) (atoi b)))
    (< (atoi a) (atoi b))
    (< a b)))

(defun sd:xd->rec (xd)
  (list (nth 0 xd) (nth 1 xd) (nth 2 xd) (nth 3 xd) (nth 4 xd)
        (cond ((nth 5 xd)) ("Thang"))
        (cond ((sd:str->nums (nth 6 xd))) ((list (nth 3 xd))))
        (sd:str->nums (nth 7 xd))))

(defun sd:same-rec (a b)
  (and (= (nth 0 a) (nth 0 b)) (= (nth 1 a) (nth 1 b)) (= (nth 5 a) (nth 5 b))
       (equal (nth 2 a) (nth 2 b) 1e-6) (equal (nth 3 a) (nth 3 b) 1e-6)
       (equal (nth 6 a) (nth 6 b) 1e-6) (equal (nth 7 a) (nth 7 b) 1e-6)))

;; Ky hieu thep thong minh (SDTHEPTM) co thanh thep da bi xoa -> bo qua khi thong ke
(defun sd:tm-orphan-p (xd / e)
  (and (= (nth 8 xd) "TM") (/= (nth 9 xd) "")
       (not (and (setq e (handent (nth 9 xd))) (entget e)))))

(defun sd:read-rebars (ss / i rec old data xd)
  (setq i 0)
  (repeat (sslength ss)
    (setq xd  (mapcar 'cdr (cdadr (assoc -3 (entget (ssname ss i) '("SD_REBAR")))))
          rec (sd:xd->rec xd)
          i   (1+ i))
    (cond
      ((sd:tm-orphan-p xd))
      ((setq old (vl-some '(lambda (x) (if (sd:same-rec x rec) x)) data))
       (setq data (subst (list (nth 0 old) (nth 1 old) (nth 2 old) (nth 3 old)
                               (+ (nth 4 old) (nth 4 rec)) (nth 5 old) (nth 6 old) (nth 7 old))
                         old data)))
      (t (setq data (cons rec data)))))
  (sd:sort data '(lambda (a b) (sd:mk< (car a) (car b)))))

;; Tach ban ghi thanh cac dong bang: thanh noi chong -> 1a, 1b... (thang)
;; dong: (so-hieu hinh-dang (kich-thuoc) d L SL/CK soCK)
(defun sd:rec-rows (r / i rows)
  (if (nth 7 r)
    (progn
      (setq i 0)
      (foreach g (sd:group (nth 7 r))
        (setq rows (cons (list (strcat (nth 0 r) (chr (+ 97 i))) "Thang" (list (car g))
                               (nth 2 r) (car g) (* (nth 1 r) (cdr g)) (nth 4 r))
                         rows)
              i (1+ i)))
      (reverse rows))
    (list (list (nth 0 r) (nth 5 r) (nth 6 r) (nth 2 r) (nth 3 r) (nth 1 r) (nth 4 r)))))

;;; --------------------------------------------------------------------------
;;;  Bang tong quat
;;;  rows: ("R" (o...) (hinh-dang kich-thuoc)|nil) | ("S" chu gia-tri) | ("W" chu)
;;; --------------------------------------------------------------------------
(defun sd:table2 (pt title cols rows shpcol sc / W xs th y rh c)
  (setq W  (* sc (apply '+ (mapcar 'cadr cols)))
        xs (sd:cumul (mapcar '(lambda (x) (* sc (cadr x))) cols))
        th (* 2.2 sc) y 0.0)
  (sd:text (sd:p+ pt (/ W 2) (* 4 sc)) title (* 4.0 sc) "MC" "SD-CHU")
  (sd:line pt (sd:p+ pt W 0) "SD-BANG")
  (foreach r (cons (list "H" (mapcar 'car cols) nil) rows)
    (setq rh (* sc (if (and (= (car r) "R") (caddr r)) 12.0 8.0)))
    (foreach x (cond ((member (car r) '("H" "R")) xs)
                     ((= (car r) "S") (list (car xs) (cadr (reverse xs)) (last xs)))
                     (t (list (car xs) (last xs))))
      (sd:line (sd:p+ pt x y) (sd:p+ pt x (- y rh)) "SD-BANG"))
    (cond ((member (car r) '("H" "R"))
           (setq c 0)
           (foreach s (cadr r)
             (if (and (= c shpcol) (caddr r))
               (sd:draw-shape (car (caddr r)) (cadr (caddr r))
                              (sd:p+ pt (+ (nth c xs) (* 6 sc)) (+ (- y rh) (* 2.5 sc)))
                              (- (nth (1+ c) xs) (nth c xs) (* 12 sc)) (- rh (* 5 sc)) sc)
               (sd:text (sd:p+ pt (/ (+ (nth c xs) (nth (1+ c) xs)) 2) (- y (/ rh 2)))
                        s th "MC" "SD-CHU"))
             (setq c (1+ c))))
          ((= (car r) "S")
           (sd:text (sd:p+ pt (* 2 sc) (- y (/ rh 2))) (cadr r) th "ML" "SD-CHU")
           (sd:text (sd:p+ pt (/ (+ (cadr (reverse xs)) (last xs)) 2) (- y (/ rh 2)))
                    (caddr r) th "MC" "SD-CHU"))
          (t (sd:text (sd:p+ pt (* 2 sc) (- y (/ rh 2))) (cadr r) th "ML" "SD-CHU")))
    (setq y (- y rh))
    (sd:line (sd:p+ pt 0 y) (sd:p+ pt W y) "SD-BANG")))

;; ---- Doc / ghi file co duong dan Unicode (thu muc / ten ban ve co chu tieng Viet co dau)
;; Ham open cua AutoLISP khong mo duoc duong dan co ky tu ngoai bang ma ANSI -> ghi / doc qua file tam
;; ten ASCII trong %TEMP%, chep qua lai bang Scripting.FileSystemObject (ho tro Unicode).
(defun sd:fso-do (meth args / fso r)
  (setq r (vl-catch-all-apply
            '(lambda ()
               (setq fso (vlax-create-object "Scripting.FileSystemObject"))
               (sd:invoke-list fso meth args))
            nil))
  (if fso (vl-catch-all-apply 'vlax-release-object (list fso)))
  (if (vl-catch-all-error-p r) nil (if (null r) t r)))
(defun sd:invoke-list (obj meth args) (apply 'vlax-invoke-method (append (list obj meth) args)))
(defun sd:fexists (fn) (or (findfile fn) (eq (sd:fso-do 'FileExists (list fn)) :vlax-true)))
(defun sd:fcopy (src dst) (sd:fso-do 'CopyFile (list src dst :vlax-true)))
(defun sd:tmpname (fn / ext)
  (setq ext (cond ((vl-filename-extension fn)) (".txt")))
  (vl-filename-mktemp "sdfile" nil ext))
;; Mo file (mode "r" / "w" / "a"); ghi nho (handle ten-that file-tam) de sd:close chep ve
(defun sd:open (fn mode / f tmp)
  (cond
    ((setq f (open fn mode)) (setq *SD:FOPEN* (cons (list f fn nil mode) *SD:FOPEN*)) f)
    ((and (setq tmp (sd:tmpname fn))
          (or (= mode "w") (not (sd:fexists fn)) (sd:fcopy fn tmp))
          (if (= mode "r") (sd:fexists fn) t)
          (setq f (open tmp mode)))
     (setq *SD:FOPEN* (cons (list f fn tmp mode) *SD:FOPEN*))
     f)))
;; Dong file; tra ve duong dan file ket qua (ten that, hoac file tam neu khong chep ve duoc)
(defun sd:close (f / e r)
  (close f)
  (setq e (assoc f *SD:FOPEN*) *SD:FOPEN* (vl-remove e *SD:FOPEN*))
  (cond ((null e) nil)
        ((null (caddr e)) (cadr e))
        ((= (nth 3 e) "r") (cadr e))
        ((sd:fcopy (caddr e) (cadr e)) (cadr e))
        (t (princ (strcat "\n[SD] Khong chep duoc ve " (cadr e) " (file dang mo?) - ket qua o: " (caddr e)))
           (caddr e))))

;; Chuoi bo dau tieng Viet (ky tu ngoai ASCII khong co trong bang -> "_")
(setq *SD:VNMAP* '((768 . "") (769 . "") (770 . "") (771 . "") (772 . "") (773 . "") (774 . "") (775 . "") (776 . "") (777 . "") (778 . "") (779 . "") (780 . "") (781 . "") (782 . "") (783 . "") (784 . "") (785 . "") (786 . "") (787 . "") (788 . "") (789 . "") (790 . "") (791 . "") (792 . "") (793 . "") (794 . "") (795 . "") (796 . "") (797 . "") (798 . "") (799 . "") (800 . "") (801 . "") (802 . "") (803 . "") (804 . "") (805 . "") (806 . "") (807 . "") (808 . "") (809 . "") (810 . "") (811 . "") (812 . "") (813 . "") (814 . "") (815 . "") (816 . "") (817 . "") (818 . "") (819 . "") (820 . "") (821 . "") (822 . "") (823 . "") (824 . "") (825 . "") (826 . "") (827 . "") (828 . "") (829 . "") (830 . "") (831 . "") (832 . "") (833 . "") (834 . "") (835 . "") (836 . "") (837 . "") (838 . "") (839 . "") (840 . "") (841 . "") (842 . "") (843 . "") (844 . "") (845 . "") (846 . "") (847 . "") (848 . "") (849 . "") (850 . "") (851 . "") (852 . "") (853 . "") (854 . "") (855 . "") (856 . "") (857 . "") (858 . "") (859 . "") (860 . "") (861 . "") (862 . "") (863 . "") (864 . "") (865 . "") (866 . "") (867 . "") (868 . "") (869 . "") (870 . "") (871 . "") (872 . "") (873 . "") (874 . "") (875 . "") (876 . "") (877 . "") (878 . "") (879 . "") (192 . "A") (193 . "A") (194 . "A") (195 . "A") (196 . "A") (197 . "A") (199 . "C") (200 . "E") (201 . "E") (202 . "E") (203 . "E") (204 . "I") (205 . "I") (206 . "I") (207 . "I") (209 . "N") (210 . "O") (211 . "O") (212 . "O") (213 . "O") (214 . "O") (217 . "U") (218 . "U") (219 . "U") (220 . "U") (221 . "Y") (224 . "a") (225 . "a") (226 . "a") (227 . "a") (228 . "a") (229 . "a") (231 . "c") (232 . "e") (233 . "e") (234 . "e") (235 . "e") (236 . "i") (237 . "i") (238 . "i") (239 . "i") (241 . "n") (242 . "o") (243 . "o") (244 . "o") (245 . "o") (246 . "o") (249 . "u") (250 . "u") (251 . "u") (252 . "u") (253 . "y") (255 . "y") (256 . "A") (257 . "a") (258 . "A") (259 . "a") (260 . "A") (261 . "a") (262 . "C") (263 . "c") (264 . "C") (265 . "c") (266 . "C") (267 . "c") (268 . "C") (269 . "c") (270 . "D") (271 . "d") (272 . "D") (273 . "d") (274 . "E") (275 . "e") (276 . "E") (277 . "e") (278 . "E") (279 . "e") (280 . "E") (281 . "e") (282 . "E") (283 . "e") (284 . "G") (285 . "g") (286 . "G") (287 . "g") (288 . "G") (289 . "g") (290 . "G") (291 . "g") (292 . "H") (293 . "h") (296 . "I") (297 . "i") (298 . "I") (299 . "i") (300 . "I") (301 . "i") (302 . "I") (303 . "i") (304 . "I") (308 . "J") (309 . "j") (310 . "K") (311 . "k") (313 . "L") (314 . "l") (315 . "L") (316 . "l") (317 . "L") (318 . "l") (323 . "N") (324 . "n") (325 . "N") (326 . "n") (327 . "N") (328 . "n") (332 . "O") (333 . "o") (334 . "O") (335 . "o") (336 . "O") (337 . "o") (340 . "R") (341 . "r") (342 . "R") (343 . "r") (344 . "R") (345 . "r") (346 . "S") (347 . "s") (348 . "S") (349 . "s") (350 . "S") (351 . "s") (352 . "S") (353 . "s") (354 . "T") (355 . "t") (356 . "T") (357 . "t") (360 . "U") (361 . "u") (362 . "U") (363 . "u") (364 . "U") (365 . "u") (366 . "U") (367 . "u") (368 . "U") (369 . "u") (370 . "U") (371 . "u") (372 . "W") (373 . "w") (374 . "Y") (375 . "y") (376 . "Y") (377 . "Z") (378 . "z") (379 . "Z") (380 . "z") (381 . "Z") (382 . "z") (416 . "O") (417 . "o") (431 . "U") (432 . "u") (461 . "A") (462 . "a") (463 . "I") (464 . "i") (465 . "O") (466 . "o") (467 . "U") (468 . "u") (469 . "U") (470 . "u") (471 . "U") (472 . "u") (473 . "U") (474 . "u") (475 . "U") (476 . "u") (478 . "A") (479 . "a") (480 . "A") (481 . "a") (486 . "G") (487 . "g") (488 . "K") (489 . "k") (490 . "O") (491 . "o") (492 . "O") (493 . "o") (496 . "j") (500 . "G") (501 . "g") (504 . "N") (505 . "n") (506 . "A") (507 . "a") (512 . "A") (513 . "a") (514 . "A") (515 . "a") (516 . "E") (517 . "e") (518 . "E") (519 . "e") (520 . "I") (521 . "i") (522 . "I") (523 . "i") (524 . "O") (525 . "o") (526 . "O") (527 . "o") (528 . "R") (529 . "r") (530 . "R") (531 . "r") (532 . "U") (533 . "u") (534 . "U") (535 . "u") (536 . "S") (537 . "s") (538 . "T") (539 . "t") (542 . "H") (543 . "h") (550 . "A") (551 . "a") (552 . "E") (553 . "e") (554 . "O") (555 . "o") (556 . "O") (557 . "o") (558 . "O") (559 . "o") (560 . "O") (561 . "o") (562 . "Y") (563 . "y") (7840 . "A") (7841 . "a") (7842 . "A") (7843 . "a") (7844 . "A") (7845 . "a") (7846 . "A") (7847 . "a") (7848 . "A") (7849 . "a") (7850 . "A") (7851 . "a") (7852 . "A") (7853 . "a") (7854 . "A") (7855 . "a") (7856 . "A") (7857 . "a") (7858 . "A") (7859 . "a") (7860 . "A") (7861 . "a") (7862 . "A") (7863 . "a") (7864 . "E") (7865 . "e") (7866 . "E") (7867 . "e") (7868 . "E") (7869 . "e") (7870 . "E") (7871 . "e") (7872 . "E") (7873 . "e") (7874 . "E") (7875 . "e") (7876 . "E") (7877 . "e") (7878 . "E") (7879 . "e") (7880 . "I") (7881 . "i") (7882 . "I") (7883 . "i") (7884 . "O") (7885 . "o") (7886 . "O") (7887 . "o") (7888 . "O") (7889 . "o") (7890 . "O") (7891 . "o") (7892 . "O") (7893 . "o") (7894 . "O") (7895 . "o") (7896 . "O") (7897 . "o") (7898 . "O") (7899 . "o") (7900 . "O") (7901 . "o") (7902 . "O") (7903 . "o") (7904 . "O") (7905 . "o") (7906 . "O") (7907 . "o") (7908 . "U") (7909 . "u") (7910 . "U") (7911 . "u") (7912 . "U") (7913 . "u") (7914 . "U") (7915 . "u") (7916 . "U") (7917 . "u") (7918 . "U") (7919 . "u") (7920 . "U") (7921 . "u") (7922 . "Y") (7923 . "y") (7924 . "Y") (7925 . "y") (7926 . "Y") (7927 . "y") (7928 . "Y") (7929 . "y")))
(defun sd:ascii-name (s / i c r e)
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq c (ascii (substr s i 1))
          r (strcat r (cond ((< c 128) (chr c)) ((setq e (assoc c *SD:VNMAP*)) (cdr e)) ("_")))
          i (1+ i)))
  r)
(defun sd:non-ascii-p (s / i r)
  (setq i 1)
  (while (and (not r) (<= i (strlen s)))
    (if (> (ascii (substr s i 1)) 127) (setq r t))
    (setq i (1+ i)))
  r)
;; Ten file xuat canh ban ve. Duong dan co chu co dau (AutoLISP open khong ghi duoc) ->
;; thu muc khong dau <o dia>:\SDOpLat_Xuat\ + ten ban ve bo dau
(defun sd:csv-name (suffix / pre nm dir)
  (setq pre (getvar "DWGPREFIX") nm (vl-filename-base (getvar "DWGNAME")))
  (if (not (sd:non-ascii-p (strcat pre nm)))
    (strcat pre nm suffix)
    (progn
      (setq dir (if (wcmatch pre "?:\\*") (strcat (substr pre 1 3) "SDOpLat_Xuat") (strcat (getenv "TEMP") "\\SDOpLat_Xuat")))
      (vl-mkdir dir)
      (if (not *SD:XUATNOTE*)
        (progn (setq *SD:XUATNOTE* t)
               (princ (strcat "\n[SD] Thu muc / ten ban ve co chu co dau: AutoCAD khong ghi file vao do duoc, file xuat luu tai " dir "\\"))))
      (strcat dir "\\" (sd:ascii-name nm) suffix))))

;;; --------------------------------------------------------------------------
;;;  Bang thong ke cot thep: du lieu, ve bang, CSV, bang tu cap nhat
;;; --------------------------------------------------------------------------
;; Du lieu bang tu cac ban ghi thep -> (rows dsum tot spliced)
;; row: (SH hinh-dang kich-thuoc DK L SL/CK soCK tongSL tongdai KL (kich-thuoc-so))
(defun sd:tk-data (data / rows tot w tl dsum rec spliced)
  (setq tot 0.0)
  (foreach r data
    (if (nth 7 r) (setq spliced t))
    ;; x = (so-hieu hinh-dang (kich-thuoc) d L SL/CK soCK)
    (foreach x (sd:rec-rows r)
      (setq tl  (/ (* (nth 4 x) (nth 5 x) (nth 6 x)) 1000.0)
            w   (* tl 0.00617 (nth 3 x) (nth 3 x))
            tot (+ tot w))
      (setq rows (cons (list (nth 0 x) (nth 1 x) (sd:join (mapcar 'sd:num (nth 2 x)) "/")
                             (sd:num (nth 3 x)) (sd:rtos (nth 4 x) 0) (itoa (nth 5 x))
                             (itoa (nth 6 x)) (itoa (* (nth 5 x) (nth 6 x)))
                             (sd:rtos tl 2) (sd:rtos w 2) (nth 2 x))
                       rows))
      (if (setq rec (assoc (nth 3 x) dsum))
        (setq dsum (subst (cons (car rec) (+ (cdr rec) w)) rec dsum))
        (setq dsum (cons (cons (nth 3 x) w) dsum)))))
  (list (reverse rows) (sd:sort dsum '(lambda (a b) (< (car a) (car b)))) tot spliced))

;; Ve bang thong ke tai pt (goc trai tren)
(defun sd:tk-table (pt tk sc / trows)
  (setq trows (mapcar '(lambda (r) (list "R" (list (nth 0 r) "" (nth 3 r) (nth 4 r) (nth 5 r)
                                                   (nth 6 r) (nth 7 r) (nth 8 r) (nth 9 r))
                                         (list (nth 1 r) (nth 10 r))))
                      (car tk)))
  (foreach x (cadr tk)
    (setq trows (append trows (list (list "S" (strcat "T\\U+1ED5ng %%c" (sd:num (car x))) (sd:rtos (cdr x) 2))))))
  (setq trows (append trows (list (list "S" "T\\U+1ED4NG C\\U+1ED8NG" (sd:rtos (caddr tk) 2)))))
  (if (cadddr tk)
    (setq trows (append trows (list (list "W" (strcat "Thanh 1a, 1b...: \\U+0111o\\U+1EA1n c\\U+1EAFt c\\U+1EE7a thanh n\\U+1ED1i ch\\U+1ED3ng; lap theo "
                                                      (sd:lapinfo) "; n\\U+1ED1i so le, <= 50% thanh / ti\\U+1EBFt di\\U+1EC7n."))))))
  (sd:table2 pt "B\\U+1EA2NG TH\\U+1ED0NG K\\U+00CA C\\U+1ED0T TH\\U+00C9P"
             '(("SH" 12) ("H\\U+00CCNH D\\U+1EA0NG" 46) ("\\U+0110K" 12) ("D\\U+00C0I (mm)" 18) ("SL/CK" 13)
               ("S\\U+1ED0 CK" 13) ("T\\U+1ED4NG SL" 16) ("T\\U+1ED4NG D\\U+00C0I (m)" 22) ("KL (kg)" 18))
             trows 1 sc))

;; Ve bang va tra ve danh sach handle cac doi tuong vua tao
(defun sd:tk-draw (pt tk sc / e0 e hs)
  (setq e0 (entlast))
  (sd:tk-table pt tk sc)
  (setq e (if e0 (entnext e0) (entnext)))
  (while e (setq hs (cons (cdr (assoc 5 (entget e))) hs) e (entnext e)))
  hs)

;; Bang tu cap nhat: ldata "SD" "TKAUTO" = (diem ty-le layout (handle...) chu-ky)
;; chu-ky = noi dung cac dong bang; chi ve lai khi noi dung thay doi (hoac force)
(defun sd:tk-all (/ ss) (if (setq ss (ssget "_X" '((0 . "CIRCLE") (-3 ("SD_REBAR"))))) (sd:tk-data (sd:read-rebars ss))))
(defun sd:tk-sig (tk) (vl-prin1-to-string (list (car tk) (cadr tk))))

(defun sd:tk-refresh (force / a e tk sig)
  (if (and (setq a (vlax-ldata-get "SD" "TKAUTO")) (= (caddr a) (getvar "CTAB")))
    (progn
      (setq tk (sd:tk-all) sig (sd:tk-sig tk))
      (if (or force (/= sig (nth 4 a)))
        (progn
          (foreach h (cadddr a) (if (and (setq e (handent h)) (entget e)) (entdel e)))
          (vlax-ldata-put "SD" "TKAUTO"
                          (list (car a) (cadr a) (caddr a) (if (car tk) (sd:tk-draw (car a) tk (cadr a))) sig))
          t)))))

;; Thu tu tang tu nhien: tach tien to chu + so (T2 < T10, B1 < T1 theo chu cai), "(chua gan)" cuoi
(defun sd:nat-key (s / i c)
  (setq i 1)
  (while (and (<= i (strlen s)) (not (wcmatch (substr s i 1) "#"))) (setq i (1+ i)))
  (list (strcase (substr s 1 (1- i))) (if (<= i (strlen s)) (atoi (substr s i)) -1) s))
(defun sd:fl< (a b / x y)
  (setq x (sd:nat-key a) y (sd:nat-key b))
  (cond ((= a b) nil) ((= a "(ch\\U+01B0a g\\U+00E1n)") nil) ((= b "(ch\\U+01B0a g\\U+00E1n)") t)
        ((/= (car x) (car y)) (< (car x) (car y)))
        ((/= (cadr x) (cadr y)) (< (cadr x) (cadr y)))
        (t (< a b))))

;;; --------------------------------------------------------------------------
;;;  SDTOIUU - Toi uu cat thep tu cay thuong pham (Best Fit Decreasing)
;;; --------------------------------------------------------------------------
;; items: ((chieu-dai . so-luong) ...) giam dan. Moi doan chiem (L + kerf),
;; suc chua 1 cay = cap + kerf (doan cuoi khong can mach cat).
;; Tra ve danh sach cay: (con-lai doan1 doan2 ...)
(defun sd:bfd (items cap kerf / bins need q best bidx i m)
  (foreach it items
    (setq need (+ (car it) kerf) q (cdr it))
    (while (> q 0)
      (setq best nil bidx nil i 0)
      (foreach b bins
        (if (and (>= (car b) (- need 1e-6)) (or (null best) (< (car b) (car best))))
          (setq best b bidx i))
        (setq i (1+ i)))
      (if (null best)
        (setq best (list (+ cap kerf))
              bins (append bins (list best))
              bidx (1- (length bins))))
      ;; cay tot nhat van la tot nhat sau khi them doan cung loai -> them 1 lan nhieu doan
      (setq m (min q (fix (/ (+ (car best) 1e-6) need))))
      (setq bins (sd:replace-nth bidx (cons (- (car best) (* m need))
                                            (append (cdr best) (sd:repeat (car it) m)))
                                 bins)
            q (- q m))))
  bins)

;;; ==========================================================================
;;;  OP LAT DA GRANITE / GACH
;;;  XDATA "SD_TILE": ma VL, loai (F nguyen / C cat chu nhat / D cat dac biet),
;;;  ma vien, w, h, dien tich, so pat, ten VL, W danh nghia, H danh nghia
;;; ==========================================================================
(defun sd:ms () (vla-get-ModelSpace (sd:doc)))
(defun sd:2d (p) (list (car p) (cadr p)))

;; Xoay, doi toa do cuc bo (goc o, goc xoay a) <-> WCS
(defun sd:rot (p a)
  (list (- (* (car p) (cos a)) (* (cadr p) (sin a)))
        (+ (* (car p) (sin a)) (* (cadr p) (cos a)))))
(defun sd:l2w (o a p / r) (setq r (sd:rot p a)) (list (+ (car o) (car r)) (+ (cadr o) (cadr r))))
(defun sd:w2l (o a p) (sd:rot (list (- (car p) (car o)) (- (cadr p) (cadr o))) (- a)))

;; Dinh cua polyline kin (doan cong chia 8)
(defun sd:curve-pts (e / o n i k pts m q d)
  (setq o (vlax-ename->vla-object e)
        n (fix (+ 0.5 (vlax-curve-getEndParam e))) i 0)
  (repeat n
    (if (equal (vla-GetBulge o i) 0.0 1e-9)
      (if (setq q (vlax-curve-getPointAtParam e i)) (setq pts (cons (sd:2d q) pts)))
      (progn
        (setq k 0 m (max 4 (min 72 (fix (+ 1.0 (/ (* 4.0 (atan (abs (vla-GetBulge o i)))) (/ pi 36.0)))))))
        (repeat m
          (if (setq q (vlax-curve-getPointAtParam e (+ i (/ k (float m))))) (setq pts (cons (sd:2d q) pts)))
          (setq k (1+ k)))))
    (setq i (1+ i)))
  (setq pts (reverse pts))
  ;; vlax-curve khong tra duoc diem (polyline loi / dinh trung): doc thang cac dinh (10) tu du lieu
  (if (< (length pts) 3)
    (progn
      (setq pts nil)
      (foreach d (entget e) (if (= (car d) 10) (setq pts (cons (list (cadr d) (caddr d)) pts))))
      (setq pts (reverse pts))))
  pts)

(defun sd:inpoly (p pts / x y in a)
  (setq x (car p) y (cadr p) a (last pts))
  (foreach b pts
    (if (and (/= (> (cadr a) y) (> (cadr b) y))
             (< x (+ (car a) (/ (* (- (car b) (car a)) (- y (cadr a))) (- (cadr b) (cadr a))))))
      (setq in (not in)))
    (setq a b))
  in)

;; Canh cua cac vong bao: (p1 p2 xmin ymin xmax ymax)
(defun sd:edges (loops / r a)
  (foreach lp loops
    (setq a (last lp))
    (foreach b lp
      (setq r (cons (list a b (min (car a) (car b)) (min (cadr a) (cadr b))
                          (max (car a) (car b)) (max (cadr a) (cadr b))) r)
            a b)))
  r)

;; Phan loai vien: "F" nam tron trong vung, "P" bi cat, nil nam ngoai
(defun sd:tile-class (cs outer holes loops edges / x0 y0 x1 y1 cross cen sides)
  (setq x0 (apply 'min (mapcar 'car cs)) x1 (apply 'max (mapcar 'car cs))
        y0 (apply 'min (mapcar 'cadr cs)) y1 (apply 'max (mapcar 'cadr cs))
        sides (mapcar 'list cs (append (cdr cs) (list (car cs)))))
  (foreach e edges
    (if (and (not cross) (<= (nth 2 e) x1) (>= (nth 4 e) x0) (<= (nth 3 e) y1) (>= (nth 5 e) y0))
      (foreach s sides
        (if (inters (car s) (cadr s) (car e) (cadr e) t) (setq cross t)))))
  (cond (cross "P")
        ((vl-some '(lambda (lp) (sd:inpoly (car lp) cs)) loops) "P")
        ((progn (setq cen (list (/ (+ x0 x1) 2.0) (/ (+ y0 y1) 2.0)))
                (and (sd:inpoly cen outer) (not (vl-some '(lambda (h) (sd:inpoly cen h)) holes))))
         "F")))

(defun sd:objarr (lst)
  (vlax-make-variant
    (vlax-safearray-fill (vlax-make-safearray vlax-vbObject (cons 0 (1- (length lst)))) lst)))

(defun sd:region (e / r)
  (setq r (vl-catch-all-apply 'vla-AddRegion
            (list (sd:ms) (sd:objarr (list (vlax-ename->vla-object e))))))
  (if (not (vl-catch-all-error-p r)) (car (vlax-safearray->list (vlax-variant-value r)))))

;; Noi cac doan thang thanh vong kin
(defun sd:chain (segs / loops pts found)
  (while segs
    (setq pts (list (car (car segs)) (cadr (car segs))) segs (cdr segs) found t)
    (while (and found segs)
      (setq found nil)
      (foreach s segs
        (if (not found)
          (cond ((equal (car s) (last pts) 1e-4)
                 (setq pts (append pts (list (cadr s))) segs (vl-remove s segs) found t))
                ((equal (cadr s) (last pts) 1e-4)
                 (setq pts (append pts (list (car s))) segs (vl-remove s segs) found t))))))
    (if (equal (car pts) (last pts) 1e-4) (setq pts (reverse (cdr (reverse pts)))))
    (setq loops (cons pts loops)))
  loops)

;; Region -> polyline (neu bien thang) hoac giu region (neu co cung). Tra ve list ename.
(defun sd:region->ents (rg lay / ex objs res)
  (setq ex (vl-catch-all-apply 'vla-Explode (list rg)))
  (if (vl-catch-all-error-p ex)
    (progn (vla-put-Layer rg lay) (list (vlax-vla-object->ename rg)))
    (progn
      (setq objs (vlax-safearray->list (vlax-variant-value ex)))
      (cond
        ((vl-every '(lambda (o) (= (vla-get-ObjectName o) "AcDbLine")) objs)
         (foreach lp (sd:chain (mapcar '(lambda (o) (list (sd:2d (vlax-get o 'StartPoint))
                                                          (sd:2d (vlax-get o 'EndPoint))))
                                       objs))
           (sd:pline lp t lay)
           (setq res (cons (entlast) res)))
         (foreach o objs (vla-Delete o))
         (vla-Delete rg)
         res)
        ((vl-every '(lambda (o) (= (vla-get-ObjectName o) "AcDbRegion")) objs)
         (vla-Delete rg)
         (apply 'append (mapcar '(lambda (o) (sd:region->ents o lay)) objs)))
        (t
         (foreach o objs (vla-Delete o))
         (vla-put-Layer rg lay)
         (list (vlax-vla-object->ename rg)))))))

;; shp: "R" vien chu nhat (ve gia cong theo w x h), "G" theo hinh that (chevron, vat...)
(defun sd:tile-xd (mat typ pc pw ph ar anc name wn hn fa thk shp)
  (list -3 (list "SD_TILE" (cons 1000 mat) (cons 1000 typ) (cons 1000 pc)
                 (cons 1040 pw) (cons 1040 ph) (cons 1040 ar) (cons 1070 anc)
                 (cons 1000 name) (cons 1040 wn) (cons 1040 hn)
                 (cons 1040 fa) (cons 1040 thk) (cons 1000 (cond (shp) ("R"))))))

(defun sd:put-xd (e xd) (entmod (append (entget e) (list xd))))

;; Pat neo (op kho): 4 pat khi rong >= 400, 2 pat khi nho hon, 0 khi canh < 150
;; o, a = he toa do cuc bo; lo = goc trai duoi vien (cuc bo). Tra ve so pat.
(defun sd:anchors (o a lo w h sc / xs)
  (cond ((< (min w h) 150.0) 0)
        (t
         (setq xs (if (>= w 400.0)
                    (list (max 100.0 (/ w 5.0)) (- w (max 100.0 (/ w 5.0))))
                    (list (/ w 2.0))))
         (foreach x xs
           (foreach y (list 0.0 h)
             (sd:dot (sd:l2w o a (list (+ (car lo) x) (+ (cadr lo) y))) (* 1.5 sc) "SD-PAT")))
         (* 2 (length xs)))))

(defun sd:tile-th (w h sc) (min (* 2.0 sc) (max (* 0.4 (min w h)) (* 0.8 sc))))

;;; --------------------------------------------------------------------------
;;;  Tien ich hinh hoc cho op lat
;;; --------------------------------------------------------------------------
(defun sd:head (n lst / r) (repeat n (setq r (cons (car lst) r) lst (cdr lst))) (reverse r))
(defun sd:tail (n lst) (repeat n (setq lst (cdr lst))) lst)
(defun sd:remove-nth (i lst / j r)
  (setq j -1)
  (foreach x lst (if (/= (setq j (1+ j)) i) (setq r (cons x r))))
  (reverse r))
(defun sd:area (pts / s a)
  (setq s 0.0 a (last pts))
  (foreach b pts (setq s (+ s (- (* (car a) (cadr b)) (* (car b) (cadr a)))) a b))
  (/ s 2.0))
(defun sd:centroid (pts)
  (list (/ (apply '+ (mapcar 'car pts)) (length pts)) (/ (apply '+ (mapcar 'cadr pts)) (length pts))))

;; Cat da giac (toa do cuc bo) bang duong x = const, giu phia lon hon (gt=T) hoac nho hon
(defun sd:ix (a b x / k)
  (setq k (/ (- x (car a)) (- (car b) (car a))))
  (list x (+ (cadr a) (* k (- (cadr b) (cadr a))))))
(defun sd:clipx (pts x gt / r a ina inb)
  (setq a (last pts))
  (foreach b pts
    (setq ina (if gt (>= (car a) x) (<= (car a) x))
          inb (if gt (>= (car b) x) (<= (car b) x)))
    (if inb
      (progn (if (not ina) (setq r (cons (sd:ix a b x) r))) (setq r (cons b r)))
      (if ina (setq r (cons (sd:ix a b x) r))))
    (setq a b))
  (reverse r))

;; Offset polyline kin vao trong (inward = T) hoac ra ngoai mot khoang d.
;; d = 0 -> tra ve chinh no. Doi tuong tam duoc xoa trong sd:finish.
(defun sd:offset (e d inward / o a0 r objs best)
  (if (<= d 1e-6)
    e
    (progn
      (setq o (vlax-ename->vla-object e) a0 (vla-get-Area o))
      (foreach s '(1.0 -1.0)
        (if (not best)
          (progn
            (setq r (vl-catch-all-apply 'vla-Offset (list o (* s d))))
            (if (not (vl-catch-all-error-p r))
              (progn
                (setq objs (vlax-safearray->list (vlax-variant-value r)))
                (if (if inward (< (vla-get-Area (car objs)) a0) (> (vla-get-Area (car objs)) a0))
                  (setq best (car (sd:sort objs '(lambda (x y) (> (vla-get-Area x) (vla-get-Area y)))))))
                (foreach x objs (if (not (eq x best)) (vla-Delete x))))))))
      (if best
        (progn (setq *SD:TMP* (cons best *SD:TMP*)) (vlax-vla-object->ename best))))))

;; Sinh vien trong toa do cuc bo: (da-giac goc-phu goc-trai-duoi rong cao)
;; goc-trai-duoi = nil voi vien khong chu nhat (chevron)
(defun sd:rectpts (x y w h) (list (list x y) (list (+ x w) y) (list (+ x w) (+ y h)) (list x (+ y h))))
(defun sd:rect-tile (x y w h) (list (sd:rectpts x y w h) 0.0 (list x y) w h))

(defun sd:gen-grid (lx0 lx1 ly0 ly1 W H jt al off / px py ox oy k s i0 i1 r)
  (setq px (+ W jt) py (+ H jt)
        ox (cond ((= al "Tam") (/ W -2.0)) ((= al "Goc") 0.0) (t (/ jt 2.0)))
        oy (cond ((= al "Tam") (/ H -2.0)) ((= al "Goc") 0.0) (t (/ jt 2.0)))
        k  (- (fix (/ (- ly0 oy) py)) 2))
  (while (<= (+ oy (* k py)) ly1)
    (setq s  (* px (rem (* k off) 1.0))
          i0 (- (fix (/ (- lx0 ox s) px)) 2)
          i1 (+ (fix (/ (- lx1 ox s) px)) 1))
    (while (<= i0 i1)
      (setq r (cons (sd:rect-tile (+ ox s (* i0 px)) (+ oy (* k py)) W H) r) i0 (1+ i0)))
    (setq k (1+ k)))
  r)

;; Xuong ca 90 do: mang tinh tien t1 = (b',b'), t2 = (-a',a'); moi nut 1 vien nam + 1 vien dung
(defun sd:gen-herring (lx0 lx1 ly0 ly1 W H jt / a b a1 b1 cs ks ms k k1 m m0 m1 x y r)
  (setq a  (max W H) b (min W H) a1 (+ a jt) b1 (+ b jt)
        cs (list (list lx0 ly0) (list lx1 ly0) (list lx1 ly1) (list lx0 ly1))
        ks (mapcar '(lambda (p) (/ (+ (car p) (cadr p)) (* 2.0 b1))) cs)
        ms (mapcar '(lambda (p) (/ (- (cadr p) (car p)) (* 2.0 a1))) cs)
        k  (- (fix (apply 'min ks)) 2) k1 (+ (fix (apply 'max ks)) 2)
        m0 (- (fix (apply 'min ms)) 2) m1 (+ (fix (apply 'max ms)) 2))
  (while (<= k k1)
    (setq m m0)
    (while (<= m m1)
      (setq x (- (* k b1) (* m a1)) y (+ (* k b1) (* m a1)))
      (foreach tl (list (list x y a b) (list (+ x a1) (- (+ y b1) a1) b a))
        (if (and (<= (car tl) lx1) (>= (+ (car tl) (caddr tl)) lx0)
                 (<= (cadr tl) ly1) (>= (+ (cadr tl) (cadddr tl)) ly0))
          (setq r (cons (apply 'sd:rect-tile tl) r))))
      (setq m (1+ m)))
    (setq k (1+ k)))
  r)

;; Chevron (xuong ca vat): vien binh hanh, 2 dau cat song song duong song (goc vat th).
;; W = dai mui-mui, H = be rong vien. Cot j tren x = j(c+mach), cot chan doc len, cot le doc xuong.
(defun sd:gen-chevron (lx0 lx1 ly0 ly1 W H jt th / tn c e p cx j j1 x0 k y up r)
  (setq tn (/ (sin th) (cos th))
        c  (* (- W (* H tn)) (cos th))
        e  (/ H (cos th))
        p  (+ e (/ jt (cos th)))
        cx (+ c jt)
        j  (- (fix (/ lx0 cx)) 2) j1 (+ (fix (/ lx1 cx)) 2))
  (while (<= j j1)
    (setq x0 (* j cx) up (= (rem (abs j) 2) 0)
          k  (- (fix (/ (- ly0 (* c tn) e) p)) 2))
    (while (<= (* k p) (+ ly1 1.0))
      (setq y (* k p))
      (setq r (cons (list (if up
                            (list (list x0 y) (list (+ x0 c) (+ y (* c tn)))
                                  (list (+ x0 c) (+ y (* c tn) e)) (list x0 (+ y e)))
                            (list (list x0 (+ y (* c tn))) (list (+ x0 c) y)
                                  (list (+ x0 c) (+ y e)) (list x0 (+ y (* c tn) e))))
                          (if up th (- th)) nil W H)
                    r)
            k (1+ k)))
    (setq j (1+ j)))
  r)

;; Ve vien vien giua eo va ei, tra ve ban ghi vien (ents w h dt loai tam lo fo fa)
(defun sd:draw-border (eo ei blen bw jt / rb res)
  (if (and eo ei (setq rb (sd:border-pieces eo ei blen jt)))
    (foreach b rb
      (sd:pline (car b) t "SD-GACH-VIEN")
      (setq res (cons (list (list (entlast)) (nth 1 b) (nth 2 b) (nth 3 b)
                            (sd:rect-typ (nth 1 b) (nth 2 b) (nth 3 b) (list blen bw))
                            (nth 4 b) (nth 5 b) (nth 6 b) (nth 7 b))
                      res)))
    (princ "\n[SD] Khong chia duoc vien vien (duong bao co cung tron hoac canh qua ngan)."))
  res)

;; Vien vien giua 2 duong offset (eo ngoai, ei trong): chia moi canh thanh vien dai lb,
;; doi xung giua canh, goc vat mitre. Tra ve ban ghi (poly w h dt tam lo fo fa) hoac nil.
(defun sd:border-pieces (eo ei lb jt / ol il n i j k best fo fa q ql smin smax tt nn s0 a b lp res ok)
  (setq ol (sd:curve-pts eo) il (sd:curve-pts ei) ok t)
  (if (/= (length ol) (length il))
    nil
    (progn
      (setq i 0)
      (foreach p il
        (if (or (null best) (< (distance p (car ol)) (car best))) (setq best (list (distance p (car ol)) i)))
        (setq i (1+ i)))
      (setq il (append (sd:tail (cadr best) il) (sd:head (cadr best) il)))
      (if (> (distance (cadr ol) (cadr il)) (distance (cadr ol) (last il)))
        (setq il (cons (car il) (reverse (cdr il)))))
      (setq n (length ol) i 0)
      (repeat n
        (setq j  (rem (1+ i) n)
              fo (nth i ol)
              fa (angle (nth i ol) (nth j ol))
              q  (list (nth i ol) (nth j ol) (nth j il) (nth i il))
              ql (mapcar '(lambda (p) (sd:w2l fo fa p)) q))
        ;; canh trong phai cung chieu canh ngoai (khong bi suy bien)
        (if (<= (- (car (nth 2 ql)) (car (nth 3 ql))) 0) (setq ok nil))
        (setq smin (apply 'min (mapcar 'car ql)) smax (apply 'max (mapcar 'car ql))
              tt   (- smax smin)
              nn   (fix (+ (/ (+ tt jt) (+ lb jt)) 0.999999))
              s0   (- smin (/ (- (* nn (+ lb jt)) jt tt) 2.0))
              k    0)
        (repeat nn
          (setq a (max smin (+ s0 (* k (+ lb jt)))) b (min smax (+ s0 (* k (+ lb jt)) lb)) k (1+ k))
          (if (> (- b a) 1.0)
            (progn
              (setq lp (sd:clipx (sd:clipx ql a t) b nil))
              (if (and (> (length lp) 2) (> (abs (sd:area lp)) 100.0))
                (setq res (cons (list (mapcar '(lambda (p) (sd:l2w fo fa p)) lp)
                                      (- (apply 'max (mapcar 'car lp)) (apply 'min (mapcar 'car lp)))
                                      (- (apply 'max (mapcar 'cadr lp)) (apply 'min (mapcar 'cadr lp)))
                                      (abs (sd:area lp))
                                      (sd:l2w fo fa (sd:centroid lp))
                                      (list (apply 'min (mapcar 'car lp)) (apply 'min (mapcar 'cadr lp)))
                                      fo fa)
                                res))))))
        (setq i (1+ i)))
      (if ok res))))

;; Gan XDATA cho 1 vien (vong dau = vien chinh, cac vong sau = lo khoet, loai "X")
(defun sd:tag-piece (p code mat name wn hn thk anct / i)
  (setq i 0)
  (foreach x (car p)
    (sd:put-xd x (sd:tile-xd mat (if (= i 0) (nth 4 p) "X") code (nth 1 p) (nth 2 p) (nth 3 p)
                             (if (= i 0) anct 0) name wn hn (nth 8 p) thk (nth 9 p)))
    (setq i (1+ i))))

;; Danh ma vien: loai F -> ma VL; vien cat gom theo kich thuoc -> MA-C1, MA-C2... (lon truoc)
;; ban ghi p = (ents w h dt loai tam lo fo fa). Tra ve (so-ma so-pat)
(defun sd:code-pieces (pieces mat name wn hn thk anc sc / grp key e cnt tc anct nanc)
  (setq nanc 0 cnt 0)
  (foreach p pieces
    (if (= (nth 4 p) "F")
      (progn
        (setq anct (if anc (sd:anchors (nth 7 p) (nth 8 p) (nth 6 p) (nth 1 p) (nth 2 p) sc) 0)
              nanc (+ nanc anct))
        (sd:tag-piece p mat mat name wn hn thk anct))
      (progn
        (setq key (if (= (nth 4 p) "C")
                    (list "C" (fix (+ 0.5 (max (nth 1 p) (nth 2 p)))) (fix (+ 0.5 (min (nth 1 p) (nth 2 p)))) 0)
                    (list "D" (fix (+ 0.5 (nth 1 p))) (fix (+ 0.5 (nth 2 p))) (fix (/ (nth 3 p) 1000.0)))))
        (if (setq e (assoc key grp))
          (setq grp (subst (cons key (cons p (cdr e))) e grp))
          (setq grp (cons (list key p) grp))))))
  (setq grp (sd:sort grp '(lambda (a b) (> (* (nth 1 (car a)) (nth 2 (car a)))
                                         (* (nth 1 (car b)) (nth 2 (car b)))))))
  (foreach g grp
    (setq cnt (1+ cnt) tc (strcat mat "-C" (itoa cnt)))
    (foreach p (cdr g)
      (setq anct (if (and anc (= (nth 4 p) "C"))
                   (sd:anchors (nth 7 p) (nth 8 p) (nth 6 p) (nth 1 p) (nth 2 p) sc) 0)
            nanc (+ nanc anct))
      (sd:tag-piece p tc mat name wn hn thk anct)
      (sd:text (sd:2d (nth 5 p)) tc (sd:tile-th (nth 1 p) (nth 2 p) sc) "MC" "SD-CHU")))
  (list cnt nanc))

(defun sd:rect-typ (w h ar full)
  (cond ((not (equal ar (* w h) (* 0.002 ar))) "D")
        ((and full (equal (max w h) (max (car full) (cadr full)) 0.5)
                   (equal (min w h) (min (car full) (cadr full)) 0.5)) "F")
        (t "C")))

;;; --------------------------------------------------------------------------
;;;  SDGACH - Chia gach / da: thang, so le, xuong ca; vien vien; khe sat tuong
;;; --------------------------------------------------------------------------
;; Cac polyline vien tao ra sau thuc the e0 (layer SD-GACH / SD-GACH-CAT / SD-GACH-VIEN, kin)
(defun sd:gach-new (e0 / e r ed)
  (setq e (if e0 (entnext e0) (entnext)))
  (while e
    (setq ed (entget e))
    (if (and ed (= (cdr (assoc 0 ed)) "LWPOLYLINE")
             (member (cdr (assoc 8 ed)) '("SD-GACH" "SD-GACH-CAT" "SD-GACH-VIEN"))
             (= 1 (logand 1 (cdr (assoc 70 ed)))))
      (setq r (cons e r)))
    (setq e (entnext e)))
  (reverse r))

(defun c:SDGACH (/ e0 sc es outer-e ssh i e holes-e mat name W H thk jt gap pat off ang al o anc lblf
                   bord bmat bw blen eo ei ef hf outer holes loops edges R tr C pa cen ents vp
                   lpts lx0 lx1 ly0 ly1 tiles lo tw th cs cls nf nanc pieces bpieces wl hl anct rc rb
                   cva hbord fa ta)
  (sd:begin)
  (setq sc (sd:sc))
  (setq es (if *SD:GBATCH* (list *SD:GOUTER*) (entsel "\nChon duong bao vung op lat (polyline kin, mat tuong / mep san): ")))
  (if (not (and es (= (cdr (assoc 0 (entget (car es)))) "LWPOLYLINE")
                (vlax-curve-isClosed (car es))))
    (princ "\n[SD] Can chon 1 polyline kin (dung PLINE, RECTANG hoac BOUNDARY de tao).")
    (progn
      (setq outer-e (car es))
      (if *SD:GBATCH*
        (setq holes-e *SD:GHOLES*)
        (progn
          (princ "\nChon cac lo / vat can ben trong (cot, hop ky thuat, cua...) <Enter neu khong co>: ")
          (if (setq ssh (ssget '((0 . "LWPOLYLINE"))))
            (progn
              (setq i 0)
              (repeat (sslength ssh)
                (setq e (ssname ssh i) i (1+ i))
                (if (and (not (eq e outer-e)) (vlax-curve-isClosed e)) (setq holes-e (cons e holes-e))))))))
      (if (not *SD:GBATCH*) (sd:vl-pick))
      ;; thong so vien (hop thoai)
      (if (not (sd:dlg "Chia vien op lat (SDGACH)"
                       (list (list "mat" "Ma vat lieu" 'str (cond (*SD:GCODE*) ("G1")))
                             (list "name" "Ten vat lieu" 'str (cond (*SD:GNAME*) ("Granite 600x600x20")))
                             (list "W" "Vien thanh pham - ngang W (mm)" 'real (cond (*SD:GW*) (600.0)))
                             (list "H" "Vien thanh pham - dung H (mm)" 'real (cond (*SD:GH*) (600.0)))
                             (list "thk" "Chieu day da / gach (mm)" 'real (cond (*SD:GT*) (20.0)))
                             (list "jt" "Be rong mach / ron (mm)" 'real0 (cond (*SD:GJ*) ((sd:cfg "RON-CU" 2.0))))
                             (list "gap" "Khe sat tuong va quanh lo (mm)" 'real0 (cond (*SD:GGAP*) (0.0)))
                             (list "pat" "Kieu lat" 'kw (cond (*SD:GPAT*) ("Thang"))
                                   '(("Thang" . "Thang") ("Sole" . "So le") ("Xuongca" . "Xuong ca 90 do")
                                     ("Chevron" . "Chevron (xuong ca vat)")))
                             (list "off" "Do so le (0.5 = 1/2 vien)" 'real 0.5 nil '("pat" "Sole"))
                             (list "cva" "Goc vat chevron (do)" 'real (cond (*SD:GCVA*) (45.0)) nil '("pat" "Chevron"))
                             (list "ang" "Goc xoay (do)" 'real0 0.0)
                             (list "al" "Diem bat dau dat o" 'kw "Mach" '(("Mach" . "Mach") ("Tam" . "Tam vien") ("Goc" . "Goc vien"))
                                   '("pat" "Thang" "Sole"))
                             (list "bord" "Lat vien vien quanh mep" 'tog nil)
                             (list "hbord" "Lat vien vien quanh cot / lo" 'tog nil)
                             (list "bmat" "Ma vien vien" 'str (cond (*SD:BCODE*) ("V1")))
                             (list "bw" "Be rong vien vien (mm)" 'real (cond (*SD:BW*) (150.0)))
                             (list "blen" "Chieu dai 1 vien vien (mm)" 'real (cond (*SD:BLEN*) (600.0)))
                             (list "anc" "Ve pat neo (op kho)" 'tog nil)
                             (list "lblf" "Ghi ma len vien nguyen" 'tog nil)
                             (list "anh" "Cat anh tam da that vao cac vien (khai bao nhu SDANHDA)" 'tog nil)
                             (list "chieu" "Chieu van tren vien (cat anh tam da)" 'kw (cond (*SD:ICHIEU*) ("Toiuu"))
                                   '(("Toiuu" . "Tu xoay 90 do de it hao") ("Doc" . "Van theo canh dai vien") ("Ngang" . "Van vuong goc canh dai") ("Chinh" . "Van theo huong vien chinh (chon 1 vien, moi vien deu 1 huong)")))
                             (list "xep" "Cach xep vien vao tam da (cat anh)" 'kw (cond (*SD:IXEP*) ("Toiuu"))
                                   '(("Toiuu" . "It hao nhat: cat xuyen, manh nho lap vao phe lieu") ("Thutu" . "Theo thu tu lat (van gan nhau)")
                                     ("Duongviem" . "Chay doc duong vien (van lien tuc)"))))))
        (exit))
      (setq mat (sd:v "mat") name (sd:v "name") W (sd:v "W") H (sd:v "H") thk (sd:v "thk") jt (sd:v "jt")
            gap (sd:v "gap") pat (sd:v "pat") *SD:GPAT* pat al (sd:v "al")
            bord (sd:v "bord") hbord (and holes-e (sd:v "hbord"))
            bmat (sd:v "bmat") bw (sd:v "bw") blen (sd:v "blen") anc (sd:v "anc") lblf (sd:v "lblf")
            *SD:BCODE* bmat *SD:BW* bw *SD:BLEN* blen
            ang (* pi (/ (sd:v "ang") 180.0)))
      (if (and (member pat '("Xuongca" "Chevron")) (equal W H 0.5))
        (progn (princ "\n[SD] Xuong ca / chevron can vien chu nhat (W khac H). Chuyen ve lat thang.")
               (setq pat "Thang")))
      (if (= pat "Chevron")
        (progn
          (setq cva (* pi (/ (sd:v "cva") 180.0)) *SD:GCVA* (sd:v "cva"))
          (if (or (>= cva (/ pi 2)) (<= (- (max W H) (* (min W H) (/ (sin cva) (cos cva)))) 0))
            (progn (princ "\n[SD] Vien qua ngan so voi goc vat (can W > H.tan(goc)). Chuyen ve lat thang.")
                   (setq pat "Thang")))))
      (setq off (if (= pat "Sole") (sd:v "off") 0.0))
      (if (not (member pat '("Thang" "Sole"))) (setq al "Mach"))
      (setq o (if *SD:GBATCH* *SD:GSTART* (sd:getpt "\nDiem bat dau chia <Enter = tam vung>: " nil)) e0 (entlast))
      (setq *SD:GCODE* mat *SD:GNAME* name *SD:GW* W *SD:GH* H *SD:GJ* (sd:cfg-put "RON-CU" jt) *SD:GGAP* gap *SD:GT* thk)
      (if (not *SD:GBATCH*) (sd:vl-save mat name W H thk jt gap pat))
      ;; duong bao vung lat chinh = bao ngoai offset vao (khe + vien + mach); lo offset ra (khe)
      (setq ef (sd:offset outer-e (+ gap (if bord (+ bw jt) 0.0)) t)
            hf (vl-remove nil (mapcar '(lambda (x) (sd:offset x (+ gap (if hbord (+ bw jt) 0.0)) nil)) holes-e)))
      (if (null ef) (progn (princ "\n[SD] Khong offset duoc duong bao (vung qua hep?).") (exit)))
      (if (null o)
        (setq o (sd:centroid (list (car (sd:bbox (sd:curve-pts ef))) (cadr (sd:bbox (sd:curve-pts ef)))))))
      (setq o (sd:2d o))
      ;; ---- vien vien
      (if bord
        (setq bpieces (sd:draw-border (sd:offset outer-e gap t) (sd:offset outer-e (+ gap bw) t) blen bw jt)))
      ;; ---- vien quanh cot / lo (bat dau tu mep lo + khe, chay ra ngoai)
      (if hbord
        (foreach x holes-e
          (setq bpieces (append bpieces
                                (sd:draw-border (sd:offset x gap nil) (sd:offset x (+ gap bw) nil) blen bw jt)))))
      ;; ---- vung lat chinh
      (setq outer (sd:curve-pts ef)
            holes (mapcar 'sd:curve-pts hf)
            loops (cons outer holes)
            edges (sd:edges loops)
            R     (sd:region ef))
      (if (null R) (progn (princ "\n[SD] Khong tao duoc region tu duong bao (tu cat nhau?).") (exit)))
      (foreach x hf (if (setq tr (sd:region x)) (vla-Boolean R 2 tr)))
      (setq lpts (mapcar '(lambda (p) (sd:w2l o ang p)) outer)
            lx0 (apply 'min (mapcar 'car lpts)) lx1 (apply 'max (mapcar 'car lpts))
            ly0 (apply 'min (mapcar 'cadr lpts)) ly1 (apply 'max (mapcar 'cadr lpts))
            tiles (cond ((= pat "Xuongca") (sd:gen-herring lx0 lx1 ly0 ly1 W H jt))
                        ((= pat "Chevron") (sd:gen-chevron lx0 lx1 ly0 ly1 (max W H) (min W H) jt cva))
                        (t (sd:gen-grid lx0 lx1 ly0 ly1 W H jt al off)))
            nf 0 nanc 0)
      (princ (strcat "\nDang xu ly " (itoa (length tiles)) " vi tri vien..."))
      (foreach tl tiles
        (setq lo (nth 2 tl) tw (nth 3 tl) th (nth 4 tl) fa (+ ang (nth 1 tl))
              cs (mapcar '(lambda (p) (sd:l2w o ang p)) (car tl))
              ta (abs (sd:area (car tl)))
              cls (sd:tile-class cs outer holes loops edges))
        (if (= cls "P")
          (progn
            (sd:pline cs t "SD-GACH-CAT")
            (setq e (entlast) tr (sd:region e))
            (entdel e)
            (setq C (vla-Copy R))
            (vla-Boolean C 1 tr)
            (setq pa (vla-get-Area C))
            (cond ((< pa 100.0) (vla-Delete C) (setq cls nil))
                  ((>= pa (* 0.999 ta)) (vla-Delete C) (setq cls "F"))
                  (t
                   (setq cen  (vlax-safearray->list (vlax-variant-value (vla-get-Centroid C)))
                         ents (sd:region->ents C "SD-GACH-CAT")
                         vp   nil)
                   (foreach x ents
                     (if (= (cdr (assoc 0 (entget x))) "LWPOLYLINE")
                       (foreach g (entget x)
                         (if (= (car g) 10) (setq vp (cons (sd:w2l o fa (cdr g)) vp))))))
                   (if (null vp) (setq vp (mapcar '(lambda (p) (sd:w2l o fa p)) cs)))
                   (setq wl (- (apply 'max (mapcar 'car vp)) (apply 'min (mapcar 'car vp)))
                         hl (- (apply 'max (mapcar 'cadr vp)) (apply 'min (mapcar 'cadr vp))))
                   (setq pieces (cons (list ents wl hl pa
                                            (if (= (length ents) 1) (sd:rect-typ wl hl pa nil) "D")
                                            cen
                                            (list (apply 'min (mapcar 'car vp)) (apply 'min (mapcar 'cadr vp)))
                                            o fa)
                                      pieces))))))
        (if (= cls "F")
          (progn
            (setq anct (if (and anc lo) (sd:anchors o ang lo tw th sc) 0))
            (sd:mk-tile-poly "SD-GACH" cs
                           (sd:tile-xd mat "F" mat tw th ta anct name W H fa thk (if lo "R" "G")))
            (setq nf (1+ nf) nanc (+ nanc anct))
            (if lblf
              (sd:text (sd:centroid cs) mat (sd:tile-th tw th sc) "MC" "SD-CHU")))))
      (setq rc (sd:code-pieces pieces mat name W H thk anc sc))
      (if bpieces (setq rb (sd:code-pieces bpieces bmat (strcat "Vien " name) blen bw thk anc sc)))
      (princ (strcat "\n[SD] " mat ": dien tich lat " (sd:rtos (/ (vla-get-Area R) 1e6) 2) " m2; "
                     (itoa nf) " vien nguyen; " (itoa (length pieces)) " vien cat (" (itoa (car rc)) " ma)"
                     (if bpieces (strcat "; vien " bmat ": " (itoa (length bpieces)) " vien ("
                                         (itoa (car rb)) " ma cat)") "")
                     (if anc (strcat "; " (itoa (+ nanc (cadr rc) (if bpieces (cadr rb) 0))) " pat") "")
                     ". Dung SDGACHTK / SDDATHO / SDGIACONG de thong ke, cat da tho, ve gia cong."))
      (vla-Delete R)
      (if (sd:v "anh")
        (progn (setq *SD:ICHIEU* (cond ((sd:v "chieu")) ("Toiuu")) *SD:IXEP* (cond ((sd:v "xep")) ("Toiuu")))
               (sd:anhda (sd:gach-new e0))))))
  (sd:finish))

(defun sd:bbox (pts)
  (list (list (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts)))
        (list (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts)))))

;;; --------------------------------------------------------------------------
;;;  SDGACHTK - Bang thong ke vien op lat + du tru so vien dat hang
;;; --------------------------------------------------------------------------
(defun sd:pc-idx (pc / p) (if (setq p (vl-string-search "-C" pc)) (atoi (substr pc (+ p 3))) 0))
(defun sd:addcnt (x n lst / e)
  (if (setq e (assoc x lst)) (subst (cons x (+ (cdr e) n)) e lst) (cons (cons x n) lst)))
(defun sd:desc (lst) (sd:sort lst '(lambda (a b) (> (car a) (car b)))))

(defun c:SDGACHTK (/ flt ss i xd key g grp mats kerf loss trows lines recs n nf nc ar anct
                     items1 items2 W H wl hl b1 b2 need order pt fn f)
  (sd:begin)
  (setq flt '((-3 ("SD_TILE"))))
  (princ "\nChon cac vien (tao bang SDGACH) <Enter = tat ca trong ban ve>: ")
  (if (not (setq ss (cond ((ssget flt)) ((ssget "_X" flt)))))
    (princ "\n[SD] Khong tim thay vien nao (dung lenh SDGACH de chia vien).")
    (progn
      (if (not (sd:dlg "Thong ke vien op lat (SDGACHTK)"
                       (list (list "kerf" "Be rong mach cat may (mm)" 'real0 3.0)
                             (list "loss" "Hao hut van chuyen / vo (%)" 'real0 3.0))))
        (exit))
      (setq kerf (sd:v "kerf") loss (sd:v "loss"))
      ;; grp: (khoa SL ename xd), xd = (maVL loai maVien w h dt pat ten W H goc day)
      (setq grp (sd:tile-groups ss))
      (foreach g grp (if (not (member (car (nth 3 g)) mats)) (setq mats (cons (car (nth 3 g)) mats))))
      (foreach mat (vl-sort mats '<)
        (setq recs (vl-remove-if-not '(lambda (g) (= (car (nth 3 g)) mat)) grp)
              recs (sd:sort recs
                     '(lambda (a b)
                        (if (/= (= (nth 1 (nth 3 a)) "F") (= (nth 1 (nth 3 b)) "F"))
                          (= (nth 1 (nth 3 a)) "F")
                          (< (sd:pc-idx (nth 2 (nth 3 a))) (sd:pc-idx (nth 2 (nth 3 b)))))))
              nf 0 nc 0 ar 0.0 anct 0 items1 nil items2 nil
              W (nth 8 (nth 3 (car recs))) H (nth 9 (nth 3 (car recs))))
        (foreach g recs
          (setq xd (nth 3 g) n (nth 1 g) wl (nth 3 xd) hl (nth 4 xd)
                ar (+ ar (* n (nth 5 xd))) anct (+ anct (* n (nth 6 xd))))
          ;; dua vien ve cung phuong voi vien nguyen W x H (vd vien dung trong xuong ca)
          (if (or (> wl (+ W 0.5)) (> hl (+ H 0.5))) (setq wl (nth 4 xd) hl (nth 3 xd)))
          (setq trows (cons (list "R" (list (nth 2 xd)
                                            (cond ((= (nth 1 xd) "F") "Nguy\\U+00EAn")
                                                  ((= (nth 1 xd) "C") "C\\U+1EAFt CN")
                                                  (t "C\\U+1EAFt \\U+0110B"))
                                            (strcat (sd:rtos wl 0) "\\U+00D7" (sd:rtos hl 0))
                                            (itoa n) (sd:rtos (/ (nth 5 xd) 1e6) 3)
                                            (sd:rtos (/ (* n (nth 5 xd)) 1e6) 2) (itoa (* n (nth 6 xd))))
                                  nil)
                            trows)
                lines (cons (sd:join (list mat (nth 2 xd) (nth 1 xd) (sd:rtos wl 0) (sd:rtos hl 0)
                                           (itoa n) (sd:rtos (/ (nth 5 xd) 1e6) 4)
                                           (sd:rtos (/ (* n (nth 5 xd)) 1e6) 3) (itoa (* n (nth 6 xd))))
                                     ";")
                            lines))
          ;; ghep doan cat tu vien nguyen: dai theo W (cao du H) hoac dai theo H (rong du W)
          (if (= (nth 1 xd) "F")
            (setq nf (+ nf n))
            (progn
              (setq nc (+ nc n))
              (cond ((>= hl (- H 0.5)) (setq items1 (sd:addcnt wl n items1)))
                    ((>= wl (- W 0.5)) (setq items2 (sd:addcnt hl n items2)))
                    (t (setq items1 (sd:addcnt wl n items1)))))))
        (setq b1    (length (sd:bfd (sd:desc items1) W kerf))
              b2    (length (sd:bfd (sd:desc items2) H kerf))
              need  (+ nf b1 b2)
              order (fix (+ (* need (+ 1.0 (/ loss 100.0))) 0.999999)))
        (setq trows (cons (list "W" (strcat mat " (" (nth 7 (nth 3 (car recs))) ") - " (sd:rtos (/ ar 1e6) 2) " m\\U+00B2 \\U+1ED1p l\\U+00E1t; " (itoa nf)
                                            " vi\\U+00EAn nguy\\U+00EAn + " (itoa nc) " vi\\U+00EAn c\\U+1EAFt (gh\\U+00E9p t\\U+1EEB "
                                            (itoa (+ b1 b2)) " vi\\U+00EAn)" (if (> anct 0) (strcat "; " (itoa anct) " p\\U+00E1t") "")))
                          trows)
              trows (cons (list "W" (strcat "   \\U+0110\\U+1EB7t h\\U+00E0ng " (sd:num W) "\\U+00D7" (sd:num H) ": " (itoa need)
                                            " + hao h\\U+1EE5t " (sd:num loss) "% = " (itoa order) " vi\\U+00EAn = "
                                            (sd:rtos (/ (* order W H) 1e6) 2) " m\\U+00B2"))
                          trows))
        (princ (strcat "\n " mat ": " (itoa nf) " vien nguyen, " (itoa nc) " vien cat -> dat "
                       (itoa order) " vien (" (sd:rtos (/ (* order W H) 1e6) 2) " m2)")))
      (setq trows (reverse trows))
      (if (setq pt (sd:getpt "\nDiem chen bang (goc trai tren): " nil))
        (sd:table2 pt "B\\U+1EA2NG TH\\U+1ED0NG K\\U+00CA VI\\U+00CAN \\U+1ED0P L\\U+00C1T"
                   '(("M\\U+00C3" 22) ("LO\\U+1EA0I" 20) ("K\\U+00CDCH TH\\U+01AF\\U+1EDAC (mm)" 32) ("SL" 12)
                     ("DT 1 VI\\U+00CAN (m\\U+00B2)" 26) ("T\\U+1ED4NG DT (m\\U+00B2)" 24) ("P\\U+00C1T" 14))
                   trows -1 (sd:sc)))
      (setq fn (sd:csv-name "_ThongKeOpLat.csv"))
      (if (setq f (sd:open fn "w"))
        (progn
          (write-line "Ma VL;Ma vien;Loai (F nguyen/C cat CN/D cat dac biet);Rong (mm);Cao (mm);SL;DT 1 vien (m2);Tong DT (m2);Pat" f)
          (foreach l (reverse lines) (write-line l f))
          (setq fn (sd:close f))
          (princ (strcat "\n[SD] Da xuat: " fn))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDCATDU - Cat du: vien cat nao, canh nao sat tuong / vat can phai cat dai ra de ra cong truong be lai cho khit
;;;  Canh bien = canh khong co vien khac nam sat ben ngoai. Moi canh bien cua vien cat duoc cong them "du" mm.
;;; --------------------------------------------------------------------------
(defun sd:cd-bbox (pts) (list (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts)) (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts))))
;; rec = (bbox pts ...): diem p co nam trong vien do khong
(defun sd:cd-in (p rec)
  (and (>= (car p) (car (car rec))) (<= (car p) (caddr (car rec))) (>= (cadr p) (cadr (car rec))) (<= (cadr p) (cadddr (car rec)))
       (sd:inpoly p (cadr rec))))
;; Cac canh bien cua da giac pts: (a b dai goc diem-ngoai); recs = (ename bbox pts xd) cua moi vien; d = khoang thu ra ngoai (mm)
(defun sd:cd-edges (pts self recs d / a r dx dy ln nx ny mx my p1 p2 po)
  (setq a (last pts))
  (foreach b pts
    (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) ln (sqrt (+ (* dx dx) (* dy dy))) po nil)
    (if (> ln 20.0)
      (progn
        (setq nx (/ (- dy) ln) ny (/ dx ln) mx (/ (+ (car a) (car b)) 2.0) my (/ (+ (cadr a) (cadr b)) 2.0)
              p1 (list (+ mx (* d nx)) (+ my (* d ny))) p2 (list (- mx (* d nx)) (- my (* d ny)))
              po (cond ((and (sd:inpoly p1 pts) (not (sd:inpoly p2 pts))) p2)
                       ((and (sd:inpoly p2 pts) (not (sd:inpoly p1 pts))) p1)))
        (if (and po (not (vl-some '(lambda (rc) (and (not (equal (car rc) self)) (sd:cd-in po (cdr rc)))) recs)))
          (setq r (cons (list a b ln (angle a b) po) r)))))
    (setq a b))
  (reverse r))
(defun sd:cd-clear (lay / ss i)
  (if (setq ss (ssget "_X" (list (cons 8 lay))))
    (progn (setq i 0) (repeat (sslength ss) (entdel (ssname ss i)) (setq i (1+ i))))))
;; Diem p (2D) cach net tuong nao do khong qua kc mm (walls = danh sach ename LINE / POLYLINE / ARC...)
(defun sd:cd-near (p walls kc)
  (vl-some '(lambda (w / q) (and (setq q (vlax-curve-getClosestPointTo w (list (car p) (cadr p) 0.0))) (< (distance p (sd:2d q)) kc))) walls))
;; dien tich da giac (mm2)
(defun sd:cd-area (pts / a s)
  (setq a (last pts) s 0.0)
  (foreach b pts (setq s (+ s (- (* (car a) (cadr b)) (* (car b) (cadr a)))) a b))
  (/ (abs s) 2.0))

;; Cac layer SD-CAODO-BAC-<mm> dang co trong ban ve: ((ten . mm) ...)
(defun sd:cd-bac-layers (/ l r nm)
  (setq l (tblnext "LAYER" t))
  (while l
    (setq nm (cdr (assoc 2 l)))
    (if (and (> (strlen nm) 13) (= (strcase (substr nm 1 13)) "SD-CAODO-BAC-") (> (atof (substr nm 14)) 0.0))
      (setq r (cons (cons nm (atof (substr nm 14))) r)))
    (setq l (tblnext "LAYER")))
  r)

;; Ghi chu rui ro khi cat du, ghi len ban ve (layer SD-CATDU-GHICHU); pt = goc tren trai
(defun sd:cd-notes (pt du kc nxt ncdo sc / lay h y notes n)
  (setq lay (sd:make-layer "SD-CATDU-GHICHU" 2 "Continuous" 18) h (* 2.5 sc) y 0.0 n 0)
  (sd:cd-clear lay)
  (setq notes
    (list (strcat "D\\U+01B0 m\\U+1EB7c \\U+0111\\U+1ECBnh " (sd:num du) " mm; kho\\U+1EA3ng s\\U+00E1t n\\U+00E9t quy t\\U+1EAFc " (sd:num kc) " mm; " (itoa ncdo) " layer \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9 SD-CAODO-BAC-mm \\U+0111\\U+01B0\\U+1EE3c nh\\U+1EADn.")
          "1. D\\U+01B0 l\\U+00E0 s\\U+1ED1 c\\U+1ED1 \\U+0111\\U+1ECBnh theo b\\U+1EA3n v\\U+1EBD thi\\U+1EBFt k\\U+1EBF. T\\U+01B0\\U+1EDDng hi\\U+1EC7n tr\\U+1EA1ng l\\U+1EC7ch / kh\\U+00F4ng vu\\U+00F4ng: \\U+0111o laser t\\U+1EA1i c\\U+00F4ng tr\\U+01B0\\U+1EDDng tr\\U+01B0\\U+1EDBc khi c\\U+1EAFt \\U+0111\\U+00E1."
          "2. Ron ho\\U+1EB7c khe l\\U+1EDBn h\\U+01A1n 8 mm (khe co gi\\U+00E3n, ron h\\U+1ED3 b\\U+01A1i) c\\U+00F3 th\\U+1EC3 b\\U+1ECB nh\\U+1EADn nh\\U+1EA7m l\\U+00E0 c\\U+1EA1nh bi\\U+00EAn v\\U+00E0 c\\U+1ED9ng d\\U+01B0 th\\U+1EEBa."
          (strcat "3. C\\U+1EA1nh s\\U+00E1t t\\U+01B0\\U+1EDDng x\\U+00E9t theo \\U+0111i\\U+1EC3m gi\\U+1EEFa c\\U+1EA1nh: c\\U+1EA1nh ch\\U+1EC9 s\\U+00E1t m\\U+1ED9t ph\\U+1EA7n v\\U+1EABn c\\U+1ED9ng d\\U+01B0 c\\U+1EA3 c\\U+1EA1nh; t\\U+01B0\\U+1EDDng v\\U+1EBD l\\U+1EC7ch qu\\U+00E1 " (sd:num kc) " mm so v\\U+1EDBi c\\U+1EA1nh vi\\U+00EAn b\\U+1ECB b\\U+1ECF s\\U+00F3t.")
          "4. S\\U+00E0n d\\U+1ED1c: k\\U+00EDch th\\U+01B0\\U+1EDBc l\\U+00E0 h\\U+00ECnh chi\\U+1EBFu b\\U+1EB1ng, ch\\U+01B0a nh\\U+00E2n chi\\U+1EC1u d\\U+00E0i th\\U+1EADt (tham kh\\U+1EA3o: d\\U+1ED1c 1:7 d\\U+00E0i th\\U+00EAm ~8 mm tr\\U+00EAn 1200, d\\U+1ED1c 1:3 ~65 mm)."
          "5. M\\U+1EB7t \\U+0111\\U+1EE9ng (\\U+1ED1p th\\U+00E0nh h\\U+1ED3, ch\\U+00E2n ng\\U+01B0\\U+1EE1ng) n\\U+1EB1m ngo\\U+00E0i l\\U+1EC7nh: t\\U+00EDnh ri\\U+00EAng."
          "6. KT c\\U+1EAFt \\U+0111\\U+00E3 c\\U+1ED9ng d\\U+01B0 ch\\U+01B0a so v\\U+1EDBi kh\\U+1ED5 t\\U+1EA5m \\U+0111\\U+00E1 th\\U+1EADt: ki\\U+1EC3m tra tr\\U+01B0\\U+1EDBc khi x\\U+1EBFp t\\U+1EA5m."
          "7. Vi\\U+00EAn s\\U+00E1t hai t\\U+01B0\\U+1EDDng c\\U+1ED9ng c\\U+1EA3 hai d\\U+01B0; vi\\U+00EAn kh\\U+00F4ng ch\\U+1EEF nh\\U+1EADt t\\U+00EDnh theo khung bao: ki\\U+1EC3m tra b\\U+1EB1ng tay."
          (if (> nxt 0) (strcat "8. C\\U+00F3 " (itoa nxt) " c\\U+1EA1nh xi\\U+00EAn: k\\U+00EDch th\\U+01B0\\U+1EDBc c\\U+1EAFt trong b\\U+1EA3ng CH\\U+01AFA c\\U+1ED9ng d\\U+01B0 c\\U+1EE7a c\\U+00E1c c\\U+1EA1nh n\\U+00E0y.") "8. C\\U+1EA1nh xi\\U+00EAn (n\\U+1EBFu c\\U+00F3): k\\U+00EDch th\\U+01B0\\U+1EDBc c\\U+1EAFt ch\\U+01B0a c\\U+1ED9ng d\\U+01B0.")
          "9. N\\U+00E9t SD-CAODO-BAC-mm l\\U+00E0 b\\U+1EA3n sao: s\\U+1EEDa n\\U+00E9t g\\U+1ED1c ph\\U+1EA3i ch\\U+1EA1y l\\U+1EA1i SDBACCAODO, x\\U+00F3a layer c\\U+0169 tr\\U+01B0\\U+1EDBc khi copy l\\U+1EA1i."))
  (sd:text pt "GHI CH\\U+00DA R\\U+1EE6I RO KHI C\\U+1EAET D\\U+01AF (SDCATDU) - \\U+0111\\U+1ED1i chi\\U+1EBFu hi\\U+1EC7n tr\\U+1EA1ng tr\\U+01B0\\U+1EDBc khi c\\U+1EAFt" (* 3.5 sc) "L" lay)
  (foreach l notes
    (setq n (1+ n))
    (sd:text (sd:p+ (sd:2d pt) 0 (- (* n 5.0 sc))) l h "L" lay))
  (princ (strcat "\n[SD] \\U+0110\\U+00E3 ghi " (itoa (1+ (length notes))) " d\\U+00F2ng ghi ch\\U+00FA r\\U+1EE7i ro l\\U+00EAn layer SD-CATDU-GHICHU.")))

(defun sd:cd-box-hit (a b g)
  (and (<= (- (car a) g) (caddr b)) (>= (+ (caddr a) g) (car b)) (<= (- (cadr a) g) (cadddr b)) (>= (+ (cadddr a) g) (cadr b))))
(defun sd:cd-box-add (a b)
  (list (min (car a) (car b)) (min (cadr a) (cadr b)) (max (caddr a) (caddr b)) (max (cadddr a) (cadddr b))))
;; gop cac hop (bbox) cham / sat nhau (khoang g) thanh cum
(defun sd:cd-cluster (boxes g / done r b hit rest)
  (setq r boxes done nil)
  (while (not done)
    (setq done t rest nil)
    (foreach b r
      (setq hit (vl-some '(lambda (x) (if (sd:cd-box-hit b x g) x)) rest))
      (if hit
        (setq rest (cons (sd:cd-box-add b hit) (vl-remove hit rest)) done nil)
        (setq rest (cons b rest))))
    (setq r rest))
  r)
;; Dam may (revision cloud) quanh hop bbox, cung ra ngoai; chord = do dai day cung mm
(defun sd:cd-cloud (bx m chord lay / x0 y0 x1 y1 pts n k a b len)
  (setq x0 (- (car bx) m) y0 (- (cadr bx) m) x1 (+ (caddr bx) m) y1 (+ (cadddr bx) m))
  (foreach seg (list (list (list x0 y0) (list x1 y0)) (list (list x1 y0) (list x1 y1)) (list (list x1 y1) (list x0 y1)) (list (list x0 y1) (list x0 y0)))
    (setq a (car seg) b (cadr seg) len (distance a b) n (max 1 (fix (+ 0.5 (/ len chord)))) k 0)
    (repeat n
      (setq pts (cons (list (+ (car a) (* (/ k (float n)) (- (car b) (car a)))) (+ (cadr a) (* (/ k (float n)) (- (cadr b) (cadr a))))) pts) k (1+ k))))
  (setq pts (reverse pts))
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1))
                   (apply 'append (mapcar '(lambda (p) (list (list 10 (car p) (cadr p)) (cons 42 0.6))) pts)))))

(defun c:SDCATDU (/ ss i e xd pts recs du mk rows key lay rc fr ang eds nl ns nx w h w2 h2 rel ed ea r trows lines pt fn f nvien lastmat ht mx my ux uy ul sc desc tuong kc rules nfree plines fn2 f2 ss2 nb eds2 mm ru kv lyr wl tk md dl ds mc cl ncdo mcl mayk bx nxt)
  (sd:begin)
  (if (setq ss (sd:select-tiles "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn (Enter = t\\U+1EA5t c\\U+1EA3 trong b\\U+1EA3n v\\U+1EBD): "))
    (if (sd:dlg "C\\U+1EAFt d\\U+01B0 s\\U+00E1t t\\U+01B0\\U+1EDDng (SDCATDU)"
                (list (list "du" "Ch\\U+1EEBa d\\U+01B0 m\\U+1EB7c \\U+0111\\U+1ECBnh m\\U+1ED7i c\\U+1EA1nh (mm; d\\U+00F9ng khi quy t\\U+1EAFc b\\U+00EAn d\\U+01B0\\U+1EDBi kh\\U+00F4ng ghi mm)" 'real (sd:cfg "CD-DU" 10.0))
                      (list "tuong" "Quy t\\U+1EAFc theo layer: layer=mm c\\U+00E1ch nhau d\\U+1EA5u ; (VD *MUIBAC*=20;*THANHHO*=15;*TUONG*=10). Ch\\U+1EC9 c\\U+1EA1nh s\\U+00E1t c\\U+00E1c n\\U+00E9t \\U+0111\\U+00F3 m\\U+1EDBi ch\\U+1EEBa d\\U+01B0. Tr\\U+1ED1ng = m\\U+1ECDi c\\U+1EA1nh bi\\U+00EAn \\U+0111\\U+1EC1u ch\\U+1EEBa d\\U+01B0" 'str (sd:cfg "CD-TUONG" ""))
                      (list "kc" "C\\U+1EA1nh coi l\\U+00E0 s\\U+00E1t khi c\\U+00E1ch n\\U+00E9t c\\U+1EE7a quy t\\U+1EAFc kh\\U+00F4ng qu\\U+00E1 (mm)" 'real0 (sd:cfg "CD-KC" 30.0))
                      (list "cdo" "T\\U+1EF1 nh\\U+1EADn c\\U+00E1c n\\U+00E9t \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9 (layer SD-CAODO-BAC-mm do SDBACCAODO t\\U+1EA1o): c\\U+1EA1nh s\\U+00E1t n\\U+00E9t \\U+0111\\U+00F3 ch\\U+1EEBa d\\U+01B0 theo s\\U+1ED1 mm c\\U+1EE7a layer" 'tog t)
                      (list "may" "Khoanh \\U+0111\\U+00E1m m\\U+00E2y quanh khu v\\U+1EF1c c\\U+00F3 ch\\U+1EEBa d\\U+01B0 (layer SD-CATDU-MAY)" 'kw (sd:cfg "CD-MAY" "Cum") '(("Cum" . "Theo c\\U+1EE5m vi\\U+00EAn li\\U+1EC1n k\\U+1EC1") ("Tung" . "T\\U+1EEBng vi\\U+00EAn") ("Khong" . "Kh\\U+00F4ng khoanh")))
                      (list "mk" "V\\U+1EBD g\\U+1EA1ch \\U+0111\\U+1ECF v\\U+00E0 ghi +d\\U+01B0 tr\\U+00EAn t\\U+1EEBng c\\U+1EA1nh (layer SD-CATDU)" 'tog t)))
      (progn
        (setq du (sd:cfg-put "CD-DU" (sd:v "du")) mk (sd:v "mk") mayk (sd:cfg-put "CD-MAY" (cond ((sd:v "may")) ("Cum"))) sc (sd:sc) i 0 nfree 0 ncdo 0 nxt 0
              tuong (vl-string-trim " " (cond ((sd:cfg-put "CD-TUONG" (cond ((sd:v "tuong")) (""))))))
              kc (sd:cfg-put "CD-KC" (cond ((sd:v "kc")) (30.0))))
        ;; quy tac: layer=mm; moi quy tac = (layer mm danh-sach-ename)
        (foreach tk (sd:split tuong ";")
          (setq tk (vl-string-trim " " tk))
          (if (/= tk "")
            (progn
              (setq kv (sd:split tk "=") lyr (vl-string-trim " " (car kv)) mm (if (and (cadr kv) (> (atof (cadr kv)) 0.0)) (atof (cadr kv)) du) wl nil)
              (if (setq ss2 (ssget "_X" (list '(0 . "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,SPLINE") (cons 8 lyr))))
                (progn
                  (setq i 0)
                  (repeat (sslength ss2) (setq wl (cons (ssname ss2 i) wl) i (1+ i)))
                  (setq rules (cons (list lyr mm wl) rules)))
                (princ (strcat "\n[SD] Kh\\U+00F4ng th\\U+1EA5y n\\U+00E9t n\\U+00E0o tr\\U+00EAn layer " lyr ": b\\U+1ECF quy t\\U+1EAFc n\\U+00E0y."))))))
        (setq rules (reverse rules))
        ;; nut doi cao do: layer SD-CAODO-BAC-<mm>, uu tien hon quy tac tay
        (if (sd:v "cdo")
          (foreach cl (sd:cd-bac-layers)
            (if (setq ss2 (ssget "_X" (list '(0 . "LINE,LWPOLYLINE,POLYLINE,ARC") (cons 8 (car cl)))))
              (progn (setq wl nil i 0)
                     (repeat (sslength ss2) (setq wl (cons (ssname ss2 i) wl) i (1+ i)))
                     (setq rules (cons (list (car cl) (cdr cl) wl) rules) ncdo (1+ ncdo))))))
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
          (if (and (>= (length xd) 12) (/= (nth 1 xd) "X"))
            (progn (setq pts (sd:curve-pts e))
                   (if (>= (length pts) 3) (setq recs (cons (list e (sd:cd-bbox pts) pts xd) recs))))))
        (sd:ho-warn '("CD-DU"))
        (setq lay (sd:make-layer "SD-CATDU" 1 "Continuous" 18) nvien 0)
        (sd:cd-clear lay)
        (sd:cd-clear "SD-CATDU-MAY")
        (foreach rc recs
          (setq xd (nth 3 rc) pts (nth 2 rc))
          (if (/= (nth 1 xd) "F")
            (progn
              (setq eds (sd:cd-edges pts (car rc) recs 8.0))
              ;; moi canh bien nhan them mm chua du (phan tu thu 6): theo quy tac dau tien co net trong khoang kc; khong quy tac nao khop = canh tu do, khong chua du
              (if (or (/= tuong "") rules)
                (progn
                  (setq nb (length eds) eds2 nil)
                  (foreach ed eds
                    (setq mm nil md (list (/ (+ (car (car ed)) (car (cadr ed))) 2.0) (/ (+ (cadr (car ed)) (cadr (cadr ed))) 2.0)))
                    (foreach ru rules (if (and (sd:cd-near md (nth 2 ru) kc) (or (null mm) (> (cadr ru) mm))) (setq mm (cadr ru))))
                    (if (and (null mm) (= tuong "")) (setq mm du))
                    (if mm (setq eds2 (cons (append ed (list mm)) eds2))))
                  (setq eds (reverse eds2) nfree (+ nfree (- nb (length eds)))))
                (setq eds (mapcar '(lambda (ed) (append ed (list du))) eds)))
              (if eds
                (progn
                  (setq fr (sd:tile-frame pts) ang (car fr) w (cadr fr) h (caddr fr) nl 0 ns 0 nx 0 dl 0.0 ds 0.0 ht (sd:tile-th w h sc))
                  (foreach ed eds
                    (setq rel (abs (rem (- (cadddr ed) ang) pi)))
                    (cond ((or (< rel 0.06) (> rel (- pi 0.06))) (setq nl (1+ nl) dl (+ dl (nth 5 ed))))
                          ((< (abs (- rel (/ pi 2.0))) 0.06) (setq ns (1+ ns) ds (+ ds (nth 5 ed))))
                          (t (setq nx (1+ nx))))
                    (if mk
                      (progn
                        (sd:line (car ed) (cadr ed) lay)
                        (setq mx (/ (+ (car (car ed)) (car (cadr ed))) 2.0) my (/ (+ (cadr (car ed)) (cadr (cadr ed))) 2.0)
                              ux (- mx (car (nth 4 ed))) uy (- my (cadr (nth 4 ed))) ul (max 1e-6 (sqrt (+ (* ux ux) (* uy uy)))))
                        (sd:text (list (+ mx (* 1.2 ht (/ ux ul))) (+ my (* 1.2 ht (/ uy ul)))) (strcat "+" (sd:num (nth 5 ed))) ht "MC" lay))))
                  (setq nxt (+ nxt nx))
                  (setq mc (cond ((sd:mv-get (car rc))) ((nth 2 xd))))
                  (setq mcl (cons (sd:cd-bbox pts) mcl))
                  (setq nvien (1+ nvien) w2 (+ w ds) h2 (+ h dl)
                        plines (cons (sd:join (list (nth 0 xd) mc (sd:rtos (car (cadddr fr)) 0) (sd:rtos (cadr (cadddr fr)) 0)
                                                    (sd:rtos w 0) (sd:rtos h 0) (itoa nl) (itoa ns) (itoa nx) (sd:rtos dl 0) (sd:rtos ds 0) (sd:rtos w2 0) (sd:rtos h2 0)) ";")
                                     plines)
                        key (strcat (nth 0 xd) "|" mc "|" (sd:rtos w2 0) "|" (sd:rtos h2 0) "|" (itoa nl) (itoa ns) (itoa nx)))
                  (if (setq r (assoc key rows))
                    (setq rows (subst (list key (nth 1 r) (nth 2 r) (nth 3 r) (nth 4 r) (nth 5 r) (nth 6 r) (nth 7 r) (nth 8 r) (nth 9 r) (1+ (nth 10 r)) (nth 11 r) (nth 12 r)) r rows))
                    (setq rows (cons (list key (nth 0 xd) mc w h nl ns nx w2 h2 1 dl ds) rows))))))))
        (if (and mcl (/= mayk "Khong"))
          (progn
            (sd:make-layer "SD-CATDU-MAY" 1 "Continuous" 25)
            (foreach bx (if (= mayk "Cum") (sd:cd-cluster mcl 60.0) mcl)
              (sd:cd-cloud bx (* 4.0 sc) (* 8.0 sc) "SD-CATDU-MAY"))
            (princ (strcat "\n[SD] \\U+0110\\U+00E3 khoanh \\U+0111\\U+00E1m m\\U+00E2y " (if (= mayk "Cum") "theo c\\U+1EE5m" "t\\U+1EEBng vi\\U+00EAn") " tr\\U+00EAn layer SD-CATDU-MAY."))))
        (if (null rows)
          (princ "\n[SD] Kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn c\\U+1EAFt n\\U+00E0o c\\U+00F3 c\\U+1EA1nh s\\U+00E1t t\\U+01B0\\U+1EDDng / v\\U+1EADt c\\U+1EA3n.")
          (progn
            (setq rows (sd:sort rows '(lambda (a b) (< (car a) (car b)))) lastmat nil)
            (foreach r rows
              (if (/= (nth 1 r) lastmat)
                (setq trows (cons (list "W" (strcat "V\\U+1EADt li\\U+1EC7u " (nth 1 r))) trows) lastmat (nth 1 r)))
              (setq desc (sd:join (vl-remove nil (list (if (> (nth 5 r) 0) (strcat (itoa (nth 5 r)) " c\\U+1EA1nh d\\U+00E0i (+" (sd:num (nth 11 r)) ")"))
                                                       (if (> (nth 6 r) 0) (strcat (itoa (nth 6 r)) " c\\U+1EA1nh ng\\U+1EAFn (+" (sd:num (nth 12 r)) ")"))
                                                       (if (> (nth 7 r) 0) (strcat (itoa (nth 7 r)) " c\\U+1EA1nh xi\\U+00EAn*")))) ", "))
              (setq trows (cons (list "R" (list (nth 2 r) (strcat (sd:rtos (nth 3 r) 0) "\\U+00D7" (sd:rtos (nth 4 r) 0)) desc
                                                (strcat (sd:rtos (nth 8 r) 0) "\\U+00D7" (sd:rtos (nth 9 r) 0)) (itoa (nth 10 r)))
                                      nil)
                                trows)
                    lines (cons (sd:join (list (nth 1 r) (nth 2 r) (sd:rtos (nth 3 r) 0) (sd:rtos (nth 4 r) 0) (itoa (nth 5 r)) (itoa (nth 6 r)) (itoa (nth 7 r)) (sd:rtos (nth 11 r) 0) (sd:rtos (nth 12 r) 0)
                                               (sd:rtos (nth 8 r) 0) (sd:rtos (nth 9 r) 0) (itoa (nth 10 r))) ";")
                                lines)))
            (setq trows (reverse trows))
            (if (> nxt 0) (princ (strcat "\n[!] " (itoa nxt) " c\\U+1EA1nh xi\\U+00EAn c\\U+00F3 v\\U+1EBD d\\U+01B0 nh\\U+01B0ng KT c\\U+1EAFt trong b\\U+1EA3ng ch\\U+01B0a c\\U+1ED9ng d\\U+01B0 c\\U+1EE7a c\\U+00E1c c\\U+1EA1nh n\\U+00E0y: t\\U+1EF1 ki\\U+1EC3m l\\U+1EA1i b\\U+1EB1ng tay.")))
            (if (> ncdo 0) (princ (strcat "\n[SD] \\U+0110\\U+00E3 nh\\U+1EADn " (itoa ncdo) " layer \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9 SD-CAODO-BAC-mm.")))
            (princ (strcat "\n[SD] " (itoa nvien) " vi\\U+00EAn c\\U+1EAFt c\\U+00F3 c\\U+1EA1nh ch\\U+1EEBa d\\U+01B0 (g\\U+1EA1ch \\U+0111\\U+1ECF + s\\U+1ED1 mm tr\\U+00EAn layer SD-CATDU)."
                           (if (> nfree 0) (strcat " " (itoa nfree) " c\\U+1EA1nh bi\\U+00EAn kh\\U+00F4ng s\\U+00E1t n\\U+00E9t n\\U+00E0o c\\U+1EE7a quy t\\U+1EAFc (m\\U+00E9p h\\U+1EDF, c\\U+1EEDa...) kh\\U+00F4ng ch\\U+1EEBa d\\U+01B0.") "")))
            (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+1EA3ng (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil))
              (sd:table2 pt "B\\U+1EA2NG C\\U+1EAET D\\U+01AF (KT C\\U+1EAET \\U+0110\\U+00C3 C\\U+1ED8NG D\\U+01AF)"
                         '(("M\\U+00C3 VI\\U+00CAN" 24) ("KT THI\\U+1EBET K\\U+1EBE (mm)" 32) ("C\\U+1EA0NH CH\\U+1EEAA D\\U+01AF" 38) ("KT C\\U+1EAET (mm)" 30) ("SL" 12))
                         trows -1 sc))
            (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n ghi ch\\U+00FA r\\U+1EE7i ro c\\U+1EAFt d\\U+01B0 (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil))
              (sd:cd-notes pt du kc nxt ncdo sc))
            (setq fn (sd:csv-name "_CatDu.csv"))
            (if (setq f (sd:open fn "w"))
              (progn
                (write-line "Ma VL;Ma vien;Rong TK;Cao TK;Canh dai;Canh ngan;Canh xien;Du canh dai;Du canh ngan;Rong cat;Cao cat;SL" f)
                (foreach l (reverse lines) (write-line l f))
                (setq fn (sd:close f))
                (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " fn))))
            ;; danh sach tung vien (toa do tam de tim lai tren ban ve / lam tem)
            (setq fn2 (sd:csv-name "_CatDuTungVien.csv"))
            (if (setq f2 (sd:open fn2 "w"))
              (progn
                (write-line "Ma VL;Ma vien;X tam;Y tam;Rong TK;Cao TK;Canh dai;Canh ngan;Canh xien;Du canh dai;Du canh ngan;Rong cat;Cao cat" f2)
                (foreach l (reverse plines) (write-line l f2))
                (setq fn2 (sd:close f2))
                (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " fn2)))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDUTOAN - Du toan tien theo don gia m2: moi ma vat lieu mot don gia (nho lai lan sau), dien tich tinh tu polyline vien
;;; --------------------------------------------------------------------------
(defun sd:money (x / s c)
  (setq x (+ x 0.5) s "")
  (while (>= x 1000.0)
    (setq c (fix (rem x 1000.0)) x (/ (- x (rem x 1000.0)) 1000.0)
          s (strcat "." (if (< c 100) "0" "") (if (< c 10) "0" "") (itoa c) s)))
  (strcat (itoa (fix x)) s))

(defun c:SDDUTOAN (/ ss i e xd pts recs mats ar prices fields k mat hao cong vat gia am tong tien trows lines pt fn f tda tcong sub tvat)
  (sd:begin)
  (if (setq ss (sd:select-tiles "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn c\\U+1EE7a ph\\U+01B0\\U+01A1ng \\U+00E1n c\\U+1EA7n d\\U+1EF1 to\\U+00E1n <Enter = t\\U+1EA5t c\\U+1EA3 trong b\\U+1EA3n v\\U+1EBD>: "))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
        (if (and (>= (length xd) 12) (/= (nth 1 xd) "X") (>= (length (setq pts (sd:curve-pts e))) 3))
          (if (setq am (assoc (nth 0 xd) ar))
            (setq ar (subst (cons (car am) (+ (cdr am) (/ (sd:cd-area pts) 1e6))) am ar))
            (setq ar (cons (cons (nth 0 xd) (/ (sd:cd-area pts) 1e6)) ar)))))
      (setq ar (vl-sort ar '(lambda (a b) (< (car a) (car b)))) prices (sd:cfg "DT-GIA" nil) k 0)
      (if (null ar)
        (princ "\n[SD] Kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn n\\U+00E0o \\U+0111\\U+1EC3 d\\U+1EF1 to\\U+00E1n.")
        (progn
          (foreach m ar
            (setq fields (cons (list (strcat "g" (itoa k)) (strcat "\\U+0110\\U+01A1n gi\\U+00E1 " (car m) " (\\U+0111\\U+1ED3ng/m\\U+00B2) - di\\U+1EC7n t\\U+00EDch " (sd:rtos (cdr m) 2) " m\\U+00B2") 'real0
                                     (cond ((cdr (assoc (car m) prices))) (0.0)))
                               fields)
                  k (1+ k)))
          (setq fields (append (reverse fields)
                               (list (list "hao" "Hao h\\U+1EE5t khi mua (%)" 'real0 (sd:cfg "DT-HAO" 5.0))
                                     (list "cong" "\\U+0110\\U+01A1n gi\\U+00E1 c\\U+00F4ng l\\U+00E1t / \\U+1ED1p (\\U+0111\\U+1ED3ng/m\\U+00B2, 0 = kh\\U+00F4ng t\\U+00EDnh)" 'real0 (sd:cfg "DT-CONG" 0.0))
                                     (list "vat" "VAT (%, 0 = ch\\U+01B0a VAT)" 'real0 (sd:cfg "DT-VAT" 0.0)))))
          (if (sd:dlg "D\\U+1EF1 to\\U+00E1n ti\\U+1EC1n theo \\U+0111\\U+01A1n gi\\U+00E1 m\\U+00B2 (SDDUTOAN)" fields)
            (progn
              (setq hao (sd:cfg-put "DT-HAO" (sd:v "hao")) cong (sd:cfg-put "DT-CONG" (sd:v "cong")) vat (sd:cfg-put "DT-VAT" (sd:v "vat"))
                    k 0 tda 0.0 tcong 0.0 prices nil)
              (foreach m ar
                (setq gia (sd:v (strcat "g" (itoa k))) k (1+ k)
                      prices (cons (cons (car m) gia) prices)
                      mat (* (cdr m) (+ 1.0 (/ hao 100.0)))
                      tien (* mat gia) tda (+ tda tien) tcong (+ tcong (* (cdr m) cong))
                      trows (cons (list "R" (list (car m) (sd:rtos (cdr m) 2) (sd:rtos mat 2) (sd:money gia) (sd:money tien)) nil) trows)
                      lines (cons (sd:join (list (car m) (sd:rtos (cdr m) 3) (sd:rtos mat 3) (sd:rtos gia 0) (sd:rtos tien 0)) ";") lines)))
              (sd:cfg-put "DT-GIA" prices)
              (setq sub (+ tda tcong) tvat (* sub (/ vat 100.0)) tong (+ sub tvat) trows (reverse trows))
              (setq trows (append trows
                                  (list (list "S" "C\\U+1ED9ng ti\\U+1EC1n \\U+0111\\U+00E1" (sd:money tda)))
                                  (if (> cong 0.0) (list (list "S" "C\\U+00F4ng l\\U+00E1t / \\U+1ED1p" (sd:money tcong))))
                                  (if (> vat 0.0) (list (list "S" (strcat "VAT " (sd:num vat) "%") (sd:money tvat))))
                                  (list (list "S" "T\\U+1ED4NG C\\U+1ED8NG (\\U+0111\\U+1ED3ng)" (sd:money tong)))))
              (princ (strcat "\n[SD] D\\U+1EF1 to\\U+00E1n: " (sd:money tong) " \\U+0111\\U+1ED3ng (\\U+0111\\U+00E1 " (sd:money tda) (if (> cong 0.0) (strcat ", c\\U+00F4ng " (sd:money tcong)) "") (if (> vat 0.0) (strcat ", VAT " (sd:money tvat)) "") ")."))
              (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+1EA3ng (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil))
                (sd:table2 pt "D\\U+1EF0 TO\\U+00C1N TI\\U+1EC0N \\U+0110\\U+00C1"
                           '(("V\\U+1EACT LI\\U+1EC6U" 30) ("DT L\\U+00C1T (m\\U+00B2)" 24) ("DT MUA (m\\U+00B2)" 24) ("\\U+0110\\U+01A0N GI\\U+00C1 (\\U+0111/m\\U+00B2)" 30) ("TH\\U+00C0NH TI\\U+1EC0N (\\U+0111)" 36))
                           trows -1 (sd:sc)))
              (setq fn (sd:csv-name "_DuToan.csv"))
              (if (setq f (sd:open fn "w"))
                (progn
                  (write-line "Ma VL;DT lat (m2);DT mua (m2);Don gia (d/m2);Thanh tien (d)" f)
                  (foreach l (reverse lines) (write-line l f))
                  (write-line (strcat "Cong tien da;;;;" (sd:rtos tda 0)) f)
                  (write-line (strcat "Cong lat;;;;" (sd:rtos tcong 0)) f)
                  (write-line (strcat "VAT;;;;" (sd:rtos tvat 0)) f)
                  (write-line (strcat "Tong cong;;;;" (sd:rtos tong 0)) f)
                  (setq fn (sd:close f))
                  (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " fn))))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDKHAOSAT - Dung phong tu so do khao sat hien trang (file CSV cua tool khao-sat-hien-trang / may do laser):
;;;  room,ab,bc,cd,da,ac,bd,height,openings_m2,source,date,note  (4 canh lien nhau + duong cheo AC dung hinh, BD de kiem tra khep)
;;;  Hang tin cay: A du 4 canh + 2 cheo va cheo khep; B 1 cheo (AC); C khong cheo (gia dinh goc B vuong); X cheo BD lech qua nguong; D thieu canh / khong khep.
;;; --------------------------------------------------------------------------
(defun sd:ks-side (a c p) (- (* (- (car c) (car a)) (- (cadr p) (cadr a))) (* (- (cadr c) (cadr a)) (- (car p) (car a)))))

;; Dung tu giac tu 4 canh + cheo AC (A goc toa do, B tren truc x). Tra ve (4-dinh gia-dinh-vuong) hoac chuoi loi
(defun sd:ks-build (ab bc cd da ac / a0 bb cc asm x y2 dx dy d aa h2 h xm ym c1 c2 dd)
  (setq a0 (list 0.0 0.0) bb (list ab 0.0))
  (if (and ac (> ac 0.0))
    (progn (setq x (/ (- (+ (* ab ab) (* ac ac)) (* bc bc)) (* 2.0 ab)) y2 (- (* ac ac) (* x x)))
           (if (>= y2 0.0) (setq cc (list x (sqrt y2)))))
    (setq cc (list ab bc) asm t))
  (if (null cc)
    "AB, BC, AC khong tao duoc tam giac"
    (progn
      (setq dx (car cc) dy (cadr cc) d (sqrt (+ (* dx dx) (* dy dy)))
            aa (/ (+ (- (* da da) (* cd cd)) (* d d)) (* 2.0 d)) h2 (- (* da da) (* aa aa)))
      (if (< h2 0.0) (setq h2 (if (<= (sqrt (- h2)) 30.0) 0.0)))
      (if (null h2)
        "so do khong khep duoc (kiem tra lai canh / duong cheo)"
        (progn
          (setq h (sqrt h2) xm (/ (* aa dx) d) ym (/ (* aa dy) d)
                c1 (list (+ xm (/ (* h dy) d)) (- ym (/ (* h dx) d)))
                c2 (list (- xm (/ (* h dy) d)) (+ ym (/ (* h dx) d)))
                dd (if (< (* (sd:ks-side a0 cc c1) (sd:ks-side a0 cc bb)) 0.0) c1 c2))
          (list (list a0 bb cc dd) asm))))))

;; v = (ab bc cd da ac bd) mm (nil = khong do). Tra ve (hang ghi-chu 4-dinh dien-tich-mm2)
(defun sd:ks-grade (v tol / r pts asm bd dev notes)
  (cond
    ((vl-some '(lambda (x) (or (null x) (<= x 0.0))) (list (nth 0 v) (nth 1 v) (nth 2 v) (nth 3 v)))
     (list "D" (list "thieu canh (can du 4 canh AB BC CD DA)") nil 0.0))
    (t
     (if (< (max (nth 0 v) (nth 1 v) (nth 2 v) (nth 3 v)) 100.0) (setq notes (list "moi canh < 100 mm: co the so do dang la met (chon don vi m)")))
     (setq r (sd:ks-build (nth 0 v) (nth 1 v) (nth 2 v) (nth 3 v) (nth 4 v)))
     (if (= (type r) 'STR)
       (list "D" (cons r notes) nil 0.0)
       (progn
         (setq pts (car r) asm (cadr r) bd (nth 5 v))
         (cond
           (asm (list "C" (cons "chua do cheo AC: gia dinh goc B vuong" notes) pts (sd:cd-area pts)))
           ((and bd (> bd 0.0))
            (setq dev (- (distance (nth 1 pts) (nth 3 pts)) bd))
            (if (> (abs dev) tol)
              (list "X" (cons (strcat "cheo BD tinh " (sd:rtos (distance (nth 1 pts) (nth 3 pts)) 0) " khac do " (sd:rtos bd 0) " (" (sd:rtos dev 0) " mm): do lai") notes) pts (sd:cd-area pts))
              (list "A" notes pts (sd:cd-area pts))))
           (t (list "B" (cons "bo sung cheo BD de kiem tra khep goc" notes) pts (sd:cd-area pts)))))))))

(defun sd:ks-num (s) (if (and s (/= (vl-string-trim " " s) "")) (atof (vl-string-translate "," "." s))))

;; Doc CSV so do: ((ten (ab bc cd da ac bd) ghichu) ...) don vi mm theo he so k
(defun sd:ks-read (fn k / f ln sep cells hdr idx rows col nm v n)
  (if (setq f (sd:open fn "r"))
    (progn
      (setq n 0)
      (while (setq ln (read-line f))
        (setq n (1+ n) ln (vl-string-trim " \t\r" ln))
        (if (and (= n 1) (>= (strlen ln) 3) (= (ascii ln) 239)) (setq ln (substr ln 4)))
        (if (/= ln "")
          (progn
            (if (null sep) (setq sep (cond ((vl-string-search ";" ln) ";") ((vl-string-search "\t" ln) "\t") (","))))
            (setq cells (sd:csv-split ln sep))
            (cond
              ((null hdr)
               (if (= (strcase (car cells)) "ROOM")
                 (setq hdr (mapcar 'strcase cells))
                 (princ "\n[SD] Dong tieu de phai bat dau bang room (room,ab,bc,cd,da,ac,bd,...).")))
              (t
               (setq nm (car cells))
               (if (and (/= nm "") (/= (strcase (substr nm 1 5)) "VI_DU"))
                 (progn
                   (setq v nil)
                   (foreach col '("AB" "BC" "CD" "DA" "AC" "BD")
                     (setq idx (vl-position col hdr)
                           v (cons (if (and idx (< idx (length cells)) (sd:ks-num (nth idx cells))) (* k (sd:ks-num (nth idx cells)))) v)))
                   (setq idx (vl-position "NOTE" hdr)
                         rows (cons (list nm (reverse v) (if (and idx (< idx (length cells))) (nth idx cells) "")) rows)))))))))
      (sd:close f)
      (reverse rows))))

(defun c:SDKHAOSAT (/ fn unit k tol dung gap rows lay x0 y0 x y rowh n cnt tot r g gr drew pts bb w h dx dy ctr sc lines nm pt)
  (sd:begin)
  (if (setq fn (getfiled "Chon file so do khao sat (.csv: room,ab,bc,cd,da,ac,bd,...)" "" "csv" 4))
    (if (sd:dlg "Dung phong tu so do khao sat (SDKHAOSAT)"
                (list (list "unit" "Don vi so do trong file" 'kw (sd:cfg "KS-UNIT" "mm") '(("mm" . "mm") ("cm" . "cm") ("m" . "met")))
                      (list "tol" "Nguong lech cheo BD / canh (mm)" 'real (sd:cfg "KS-TOL" 10.0))
                      (list "dung" "Dung cac phong hang" 'kw (sd:cfg "KS-DUNG" "AB")
                            '(("A" . "Chi hang A (du 4 canh + 2 cheo, khep) - dung cho shop drawing") ("AB" . "A va B (co cheo AC)") ("ABC" . "A, B, C (C gia dinh goc vuong)") ("Tat" . "Ca hang X (cheo lech): chi de xem")))
                      (list "gap" "Khoang cach giua cac phong khi xep (mm)" 'real (sd:cfg "KS-GAP" 2000.0))))
      (progn
        (setq unit (sd:cfg-put "KS-UNIT" (sd:v "unit")) tol (sd:cfg-put "KS-TOL" (sd:v "tol")) dung (sd:cfg-put "KS-DUNG" (sd:v "dung"))
              gap (sd:cfg-put "KS-GAP" (sd:v "gap")) sc (sd:sc)
              k (cond ((= unit "cm") 10.0) ((= unit "m") 1000.0) (1.0))
              rows (sd:ks-read fn k))
        (if (null rows)
          (princ "\n[SD] Khong doc duoc phong nao trong file.")
          (if (setq pt (sd:getpt "\nDiem chen phong dau tien (goc trai duoi): " nil))
            (progn
              (setq lay (sd:make-layer "SD-PHONG" 3 "Continuous" 25) x0 (car pt) y0 (cadr pt) x x0 y y0 rowh 0.0 cnt 0 drew 0 tot 0.0)
              (foreach r rows
                (setq g (sd:ks-grade (cadr r) tol) gr (car g) cnt (1+ cnt) nm (car r)
                      lines (cons (list nm gr (cadr g) (cadddr g)) lines))
                (if (and (caddr g) (wcmatch gr (cond ((= dung "A") "A") ((= dung "AB") "[AB]") ((= dung "ABC") "[ABC]") ("[ABCX]"))))
                  (progn
                    (setq pts (caddr g) bb (sd:cd-bbox pts) w (- (caddr bb) (car bb)) h (- (cadddr bb) (cadr bb)))
                    (if (and (> (- x x0) 0.0) (> (+ (- x x0) w) 80000.0)) (setq x x0 y (- y rowh gap) rowh 0.0))
                    (setq dx (- x (car bb)) dy (- y (cadr bb)))
                    (sd:pline (mapcar '(lambda (q) (list (+ (car q) dx) (+ (cadr q) dy))) pts) t lay)
                    (setq ctr (list (+ (car bb) dx (/ w 2.0)) (+ (cadr bb) dy (/ h 2.0))))
                    (sd:text ctr (strcat nm "  [" gr "]") (* 3.0 sc) "MC" lay)
                    (sd:text (list (car ctr) (- (cadr ctr) (* 5.0 sc))) (strcat "S = " (sd:rtos (/ (cadddr g) 1e6) 2) " m\\U+00B2") (* 2.5 sc) "MC" lay)
                    (setq x (+ x w gap) rowh (max rowh h) drew (1+ drew) tot (+ tot (cadddr g))))))
              (princ (strcat "\n[SD] Khao sat: " (itoa cnt) " phong, dung " (itoa drew) " phong (hang " dung "), tong " (sd:rtos (/ tot 1e6) 2) " m\\U+00B2 (tu toa do dung hinh)."))
              (foreach l (reverse lines)
                (if (or (/= (cadr l) "A") (caddr l))
                  (princ (strcat "\n  " (car l) " [" (cadr l) "]" (if (caddr l) (strcat ": " (sd:join (caddr l) "; ")) "")))))
              (princ "\n   Dung polyline phong lam bien cho SDGACH / SDLOT / SDRAITAM. Shop drawing op lat chi nen dung phong hang A; B, C can do them cheo truoc khi dat vat tu.")))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDCHIABAC - Chia bac thang tu cao do: cao do hoan thien 2 san (so voi +-0.000 cong trinh) + so bac tung ve ->
;;;  chieu cao bac (lam tron, don phan lech vao cac bac tren cung hoac duoi cung), bang cao do hoan thien / ket cau cua tung bac va chieu nghi
;;; --------------------------------------------------------------------------
;; n bac, tong chieu cao total (mm), tron = buoc lam tron (mm, 0 = giu so le), top = T don phan lech len cac bac tren cung, nil = duoi cung.
;; Tra ve danh sach n chieu cao bac (mm) tu duoi len, tong dung bang total
(defun sd:cb-heights (n total tron top / base r diff m k res i lst h sg)
  (setq base (/ total n))
  (if (<= tron 0.0)
    (repeat n (setq lst (cons base lst)))
    (progn
      (setq r (* tron (fix (+ 0.5 (/ base tron)))) diff (- total (* r n))
            m (fix (+ (if (< diff 0.0) -0.5 0.5) (/ diff tron))) k (abs m) sg (if (< m 0) -1.0 1.0)
            res (- diff (* m tron)) i 0)
      (repeat n
        (setq h r)
        (if (if top (>= i (- n k)) (< i k)) (setq h (+ h (* sg tron))))
        (if (= i (if top (1- n) 0)) (setq h (+ h res)))
        (setq lst (cons h lst) i (1+ i)))
      (setq lst (reverse lst))))
  lst)

;; Hang bang cao do: ((nhan cao-do-hoan-thien cao-do-ket-cau cao-bac ghi-chu) ...); flights = so bac tung ve; lop = day da + vua (mm)
(defun sd:cb-rows (z0 hs flights lop / z k r nf j h)
  (setq z z0 k 0 nf 0)
  (foreach fl flights
    (setq nf (1+ nf))
    (repeat fl
      (setq h (nth k hs) z (+ z h) k (1+ k))
      (setq r (cons (list (strcat "B\\U+1EACC " (itoa k)) z (- z lop) h "") r)))
    (if (< nf (length flights))
      (setq r (cons (list (strcat "CHI\\U+1EBEU NGH\\U+1EC8 " (itoa nf)) z (- z lop) nil "") r))))
  (reverse r))

(defun sd:cb-flights (s / r v)
  (foreach tk (sd:split s ",")
    (setq v (atoi (vl-string-trim " " tk)))
    (if (> v 0) (setq r (cons v r))))
  (reverse r))

(defun c:SDCHIABAC (/ z0 z1 chia fl n total tron top da vua lop hs rows trows pt hmin hmax nom st)
  (sd:begin)
  (if (sd:dlg "Chia b\\U+1EADc thang t\\U+1EEB cao \\U+0111\\U+1ED9 (SDCHIABAC)"
              (list (list "z0" "Cao \\U+0111\\U+1ED9 ho\\U+00E0n thi\\U+1EC7n s\\U+00E0n d\\U+01B0\\U+1EDBi so v\\U+1EDBi \\U+00B10.000 c\\U+00F4ng tr\\U+00ECnh (m)" 'real (sd:cfg "CB-Z0" 0.0))
                    (list "z1" "Cao \\U+0111\\U+1ED9 ho\\U+00E0n thi\\U+1EC7n s\\U+00E0n tr\\U+00EAn (m)" 'real (sd:cfg "CB-Z1" 3.5))
                    (list "chia" "S\\U+1ED1 b\\U+1EADc t\\U+1EEBng v\\U+1EBF, c\\U+00E1ch nhau d\\U+1EA5u ph\\U+1EA9y (VD 10,11; m\\U+1ED9t v\\U+1EBF: 21). Chi\\U+1EBFu ngh\\U+1EC9 n\\U+1EB1m gi\\U+1EEFa c\\U+00E1c v\\U+1EBF" 'str (sd:cfg "CB-CHIA" "21"))
                    (list "tron" "L\\U+00E0m tr\\U+00F2n chi\\U+1EC1u cao b\\U+1EADc t\\U+1EDBi (mm; 0 = gi\\U+1EEF s\\U+1ED1 l\\U+1EBB)" 'real0 (sd:cfg "CB-TRON" 1.0))
                    (list "don" "Ph\\U+1EA7n l\\U+1EC7ch do l\\U+00E0m tr\\U+00F2n d\\U+1ED3n v\\U+00E0o" 'kw (sd:cfg "CB-DON" "Tren")
                          '(("Tren" . "C\\U+00E1c b\\U+1EADc tr\\U+00EAn c\\U+00F9ng (b\\U+1EADc tr\\U+00EAn th\\U+1EA5p h\\U+01A1n ho\\U+1EB7c cao h\\U+01A1n m\\U+1ED9t ch\\U+00FAt)") ("Duoi" . "C\\U+00E1c b\\U+1EADc d\\U+01B0\\U+1EDBi c\\U+00F9ng")))
                    (list "da" "\\U+0110\\U+00E1 m\\U+1EB7t b\\U+1EADc / s\\U+00E0n d\\U+00E0y (mm)" 'real0 (sd:cfg "CB-DA" 20.0))
                    (list "vua" "L\\U+1EDBp v\\U+1EEFa / h\\U+1ED3 d\\U+1EA7u d\\U+01B0\\U+1EDBi \\U+0111\\U+00E1 (mm)" 'real0 (sd:cfg "CB-VUA" 30.0))
                    (list "st" "\\U+0110\\U+1EB7t lu\\U+00F4n chi\\U+1EC1u cao b\\U+1EADc v\\U+00E0 s\\U+1ED1 b\\U+1EADc v\\U+1EBF \\U+0111\\U+1EA7u cho SDTHANGDA" 'tog t)))
    (progn
      (setq z0 (sd:cfg-put "CB-Z0" (sd:v "z0")) z1 (sd:cfg-put "CB-Z1" (sd:v "z1")) chia (sd:cfg-put "CB-CHIA" (sd:v "chia"))
            tron (sd:cfg-put "CB-TRON" (cond ((sd:v "tron")) (0.0))) top (= (sd:cfg-put "CB-DON" (sd:v "don")) "Tren")
            da (sd:cfg-put "CB-DA" (cond ((sd:v "da")) (0.0))) vua (sd:cfg-put "CB-VUA" (cond ((sd:v "vua")) (0.0)))
            lop (+ da vua) fl (sd:cb-flights chia) n (apply '+ (cons 0 fl)) total (* 1000.0 (- z1 z0)))
      (cond
        ((null fl) (princ "\n[SD] S\\U+1ED1 b\\U+1EADc t\\U+1EEBng v\\U+1EBF kh\\U+00F4ng h\\U+1EE3p l\\U+1EC7 (VD 10,11)."))
        ((<= total 0.0) (princ "\n[SD] Cao \\U+0111\\U+1ED9 s\\U+00E0n tr\\U+00EAn ph\\U+1EA3i l\\U+1EDBn h\\U+01A1n cao \\U+0111\\U+1ED9 s\\U+00E0n d\\U+01B0\\U+1EDBi."))
        (t
         (setq hs (sd:cb-heights n total tron top)
               hmin (apply 'min hs) hmax (apply 'max hs)
               rows (sd:cb-rows (* 1000.0 z0) hs fl lop))
         (princ (strcat "\n[SD] " (itoa n) " b\\U+1EADc, chi\\U+1EC1u cao t\\U+1EA7ng " (sd:rtos total 1) " mm: b\\U+1EADc " (sd:rtos hmin 1)
                        (if (> (- hmax hmin) 0.05) (strcat " \\U+0111\\U+1EBFn " (sd:rtos hmax 1)) "") " mm (chia ch\\U+00EDnh x\\U+00E1c " (sd:rtos (/ total n) 2) ")."))
         (if (or (< hmin 150.0) (> hmax 180.0))
           (princ "\n[!] Chi\\U+1EC1u cao b\\U+1EADc ngo\\U+00E0i kho\\U+1EA3ng 150 - 180 mm: ki\\U+1EC3m tra s\\U+1ED1 b\\U+1EADc ho\\U+1EB7c cao \\U+0111\\U+1ED9."))
         (if (> (- hmax hmin) 0.05)
           (princ (strcat "\n   L\\U+00E0m tr\\U+00F2n t\\U+1EDBi " (sd:num tron) " mm n\\U+00EAn c\\U+00E1c b\\U+1EADc kh\\U+00F4ng \\U+0111\\U+1EC1u nhau, ch\\U+00EAnh t\\U+1ED1i \\U+0111a " (sd:rtos (- hmax hmin) 1) " mm; b\\U+1EADc l\\U+1EC7ch n\\U+1EB1m \\U+1EDF ph\\U+1EA7n " (if top "tr\\U+00EAn" "d\\U+01B0\\U+1EDBi") " c\\U+00F9ng c\\U+1EE7a thang.")))
         (foreach r rows
           (princ (strcat "\n  " (car r) ": ho\\U+00E0n thi\\U+1EC7n " (sd:rtos (/ (cadr r) 1000.0) 3) " | k\\U+1EBFt c\\U+1EA5u " (sd:rtos (/ (caddr r) 1000.0) 3)
                          (if (cadddr r) (strcat " | b\\U+1EADc " (sd:rtos (cadddr r) 1)) ""))))
         (setq trows (cons (list "R" (list "S\\U+00C0N D\\U+01AF\\U+1EDAI" (sd:rtos z0 3) (sd:rtos (- z0 (/ lop 1000.0)) 3) "" "") nil) trows))
         (foreach r rows
           (setq trows (cons (list "R" (list (car r) (sd:rtos (/ (cadr r) 1000.0) 3) (sd:rtos (/ (caddr r) 1000.0) 3)
                                             (if (cadddr r) (sd:rtos (cadddr r) 1) "") (if (cadddr r) "" "chi\\U+1EBFu ngh\\U+1EC9"))
                                   nil)
                             trows)))
         (setq trows (reverse trows))
         (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+1EA3ng cao \\U+0111\\U+1ED9 (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil))
           (sd:table2 pt "B\\U+1EA2NG CAO \\U+0110\\U+1ED8 B\\U+1EACC THANG (m, SO V\\U+1EDAI \\U+00B10.000)"
                      '(("B\\U+1EACC" 28) ("CAO \\U+0110\\U+1ED8 HO\\U+00C0N THI\\U+1EC6N" 36) ("CAO \\U+0110\\U+1ED8 K\\U+1EBET C\\U+1EA4U" 36) ("CAO B\\U+1EACC (mm)" 28) ("GHI CH\\U+00DA" 28))
                      trows -1 (sd:sc)))
         (if (sd:v "st")
           (progn
             (setq nom (if (> tron 0.0) (* tron (fix (+ 0.5 (/ (/ total n) tron)))) (/ total n)))
             (sd:cfg-put "ST-R" nom) (sd:cfg-put "ST-N" (car fl))
             (princ (strcat "\n[SD] SDTHANGDA: chi\\U+1EC1u cao b\\U+1EADc \\U+0111\\U+1EB7t " (sd:rtos nom 1) " mm, s\\U+1ED1 b\\U+1EADc " (itoa (car fl)) " (v\\U+1EBF \\U+0111\\U+1EA7u); b\\U+1EADc l\\U+1EC7ch x\\U+1EED l\\U+00FD ri\\U+00EAng n\\U+1EBFu c\\U+1EA7n.")))))))
    )
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDMAVIEN - Ma vien theo hinh dang: cac vien cung vat lieu va cung hinh dang (xoay duoc, tuy chon doi xung guong) co cung ma (VD G1-01).
;;;  Ma ghi vao vien (xdata SD_MAVIEN) va nho trong ban ve: chay lai thi vien cu giu ma cu, hinh moi nhan ma tiep theo.
;;; --------------------------------------------------------------------------
;; Da giac nguoc chieu kim dong ho neu can (CCW)
(defun sd:mv-orient (pts / a s)
  (setq a (last pts) s 0.0)
  (foreach b pts (setq s (+ s (- (* (car a) (cadr b)) (* (car b) (cadr a)))) a b))
  (if (< s 0.0) (reverse pts) pts))

;; Bo dinh trung / thang hang (goc re < 0.1 do)
(defun sd:mv-clean (pts / r n i p0 p1 p2 d1x d1y d2x d2y)
  (setq n (length pts) i 0)
  (repeat n
    (setq p0 (nth (rem (+ i n -1) n) pts) p1 (nth i pts) p2 (nth (rem (1+ i) n) pts)
          d1x (- (car p1) (car p0)) d1y (- (cadr p1) (cadr p0)) d2x (- (car p2) (car p1)) d2y (- (cadr p2) (cadr p1)))
    (if (> (abs (atan (- (* d1x d2y) (* d1y d2x)) (+ (* d1x d2x) (* d1y d2y)))) 0.0017) (setq r (cons p1 r)))
    (setq i (1+ i)))
  (reverse r))

;; Day token "dai/goc-re" cua da giac CCW (dai lam tron theo tol mm, goc re tron 1 do)
(defun sd:mv-seq (pts tol / n i p1 p2 p3 d1x d1y d2x d2y r)
  (setq n (length pts) i 0)
  (repeat n
    (setq p1 (nth i pts) p2 (nth (rem (1+ i) n) pts) p3 (nth (rem (+ i 2) n) pts)
          d1x (- (car p2) (car p1)) d1y (- (cadr p2) (cadr p1)) d2x (- (car p3) (car p2)) d2y (- (cadr p3) (cadr p2)))
    (setq r (cons (strcat (itoa (fix (+ 0.5 (/ (sqrt (+ (* d1x d1x) (* d1y d1y))) tol)))) "/"
                          (itoa (fix (+ 0.5 (* (/ 180.0 pi) (atan (- (* d1x d2y) (* d1y d2x)) (+ (* d1x d2x) (* d1y d2y))))))))
                  r)
          i (1+ i)))
  (reverse r))

;; Chuoi nho nhat trong cac phep quay diem bat dau cua day token (khong phu thuoc diem dau / huong xoay vien)
(defun sd:mv-canon (seq / n k best str i)
  (setq n (length seq) k 0)
  (repeat n
    (setq str "" i 0)
    (repeat n (setq str (strcat str (nth (rem (+ k i) n) seq) ";") i (1+ i)))
    (if (or (null best) (< str best)) (setq best str))
    (setq k (1+ k)))
  best)

(defun sd:mv-key (pts tol mirror / p a b)
  (setq p (sd:mv-clean (sd:mv-orient pts)) a (sd:mv-canon (sd:mv-seq p tol)))
  (if mirror
    (progn
      (setq b (sd:mv-canon (sd:mv-seq (sd:mv-orient (mapcar '(lambda (q) (list (- (car q)) (cadr q))) p)) tol)))
      (if (< b a) (setq a b))))
  a)

;; Ma viec da ghi tren viec e (nil neu chua co)
(defun sd:mv-get (e)
  (car (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_MAVIEN")))))))

;; So thu tu lon nhat da dung voi tien to pre trong bang map ((khoa . ma) ...)
(defun sd:mv-max (map pre / m n)
  (setq m 0)
  (foreach kv map
    (if (and (> (strlen (cdr kv)) (1+ (strlen pre))) (= (substr (cdr kv) 1 (1+ (strlen pre))) (strcat pre "-")))
      (progn (setq n (atoi (substr (cdr kv) (+ 2 (strlen pre))))) (if (> n m) (setq m n)))))
  m)

(defun c:SDMAVIEN (/ ss tol mir pre pfx re mk map i e xd pts key mat code np g groups fr lay sc trows lines pl pt fn f nnew nold cls)
  (sd:begin)
  (if (setq ss (sd:select-tiles "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn c\\U+1EA7n \\U+0111\\U+00E1nh m\\U+00E3 <Enter = t\\U+1EA5t c\\U+1EA3 trong b\\U+1EA3n v\\U+1EBD>: "))
    (if (sd:dlg "M\\U+00E3 vi\\U+00EAn theo h\\U+00ECnh d\\U+1EA1ng (SDMAVIEN)"
                (list (list "tol" "Dung sai k\\U+00EDch th\\U+01B0\\U+1EDBc coi l\\U+00E0 c\\U+00F9ng h\\U+00ECnh (mm)" 'real (sd:cfg "MV-TOL" 1.0))
                      (list "mir" "G\\U+1ED9p c\\U+1EA3 vi\\U+00EAn \\U+0111\\U+1ED1i x\\U+1EE9ng g\\U+01B0\\U+01A1ng (VD hai vi\\U+00EAn ch\\U+1EEF L \\U+0111\\U+1ED1i x\\U+1EE9ng)" 'tog (sd:cfg "MV-MIR" nil))
                      (list "pre" "Ti\\U+1EC1n t\\U+1ED1 m\\U+00E3" 'kw (sd:cfg "MV-PRE" "Mat") '(("Mat" . "M\\U+00E3 v\\U+1EADt li\\U+1EC7u (VD G1-01)") ("Co" . "Ti\\U+1EC1n t\\U+1ED1 c\\U+1ED1 \\U+0111\\U+1ECBnh b\\U+00EAn d\\U+01B0\\U+1EDBi")))
                      (list "pfx" "Ti\\U+1EC1n t\\U+1ED1 c\\U+1ED1 \\U+0111\\U+1ECBnh (VD ST)" 'str (sd:cfg "MV-PFX" "ST") nil '("pre" "Co"))
                      (list "re" "\\U+0110\\U+00E1nh l\\U+1EA1i t\\U+1EEB \\U+0111\\U+1EA7u (b\\U+1ECF b\\U+1EA3ng m\\U+00E3 \\U+0111\\U+00E3 nh\\U+1EDB)" 'tog nil)
                      (list "mk" "Ghi m\\U+00E3 l\\U+00EAn t\\U+1EEBng vi\\U+00EAn (layer SD-MAVIEN)" 'tog t)))
      (progn
        (setq tol (sd:cfg-put "MV-TOL" (sd:v "tol")) mir (sd:cfg-put "MV-MIR" (sd:v "mir")) pre (sd:cfg-put "MV-PRE" (sd:v "pre"))
              pfx (vl-string-trim " " (cond ((sd:cfg-put "MV-PFX" (cond ((sd:v "pfx")) ("ST"))))))
              re (sd:v "re") mk (sd:v "mk") sc (sd:sc) nnew 0 nold 0
              map (if re nil (vlax-ldata-get "SD" "MAVIEN-MAP")))
        (regapp "SD_MAVIEN")
        (setq lay (sd:make-layer "SD-MAVIEN" 4 "Continuous" 13))
        (sd:cd-clear lay)
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
          (if (and (>= (length xd) 12) (/= (nth 1 xd) "X") (>= (length (setq pts (sd:curve-pts e))) 3))
            (progn
              (setq mat (nth 0 xd) key (strcat mat "|" (sd:mv-key pts tol mir)))
              (if (setq code (cdr (assoc key map)))
                (setq nold (1+ nold))
                (progn
                  (setq np (if (= pre "Mat") mat (if (= pfx "") "ST" pfx))
                        code (strcat np "-" (sd:khi-num2 (1+ (sd:mv-max map np))))
                        map (append map (list (cons key code))) nnew (1+ nnew))))
              (entmod (append (entget e) (list (list -3 (list "SD_MAVIEN" (cons 1000 code))))))
              (setq fr (sd:tile-frame pts))
              (if (setq g (assoc code groups))
                (setq groups (subst (list code (1+ (nth 1 g)) (nth 2 g) (nth 3 g) (+ (nth 4 g) (/ (sd:cd-area pts) 1e6)) (nth 5 g) (nth 6 g) (nth 7 g)) g groups))
                (setq groups (cons (list code 1 mat (nth 1 xd) (/ (sd:cd-area pts) 1e6) (cadr fr) (caddr fr) nil) groups)))
              (setq pl (cons (list code (car (cadddr fr)) (cadr (cadddr fr)) mat) pl))
              (if mk (sd:text (cadddr fr) code (sd:tile-th (cadr fr) (caddr fr) sc) "MC" lay)))))
        (vlax-ldata-put "SD" "MAVIEN-MAP" map)
        (setq groups (sd:sort groups '(lambda (a b) (< (car a) (car b)))))
        (foreach g groups
          (setq cls (cond ((= (nth 3 g) "F") "Nguy\\U+00EAn") ((= (nth 3 g) "C") "C\\U+1EAFt ch\\U+1EEF nh\\U+1EADt") (t "C\\U+1EAFt \\U+0111\\U+1EB7c bi\\U+1EC7t"))
                trows (cons (list "R" (list (car g) cls (strcat (sd:rtos (max (nth 5 g) (nth 6 g)) 0) "\\U+00D7" (sd:rtos (min (nth 5 g) (nth 6 g)) 0))
                                            (itoa (nth 1 g)) (sd:rtos (nth 4 g) 2))
                                  nil)
                            trows)
                lines (cons (sd:join (list (car g) (nth 2 g) cls (sd:rtos (max (nth 5 g) (nth 6 g)) 0) (sd:rtos (min (nth 5 g) (nth 6 g)) 0) (itoa (nth 1 g)) (sd:rtos (nth 4 g) 3)) ";") lines)))
        (setq trows (reverse trows))
        (princ (strcat "\n[SD] " (itoa (+ nnew nold)) " vi\\U+00EAn, " (itoa (length groups)) " m\\U+00E3 (" (itoa nnew) " vi\\U+00EAn thu\\U+1ED9c h\\U+00ECnh m\\U+1EDBi, " (itoa nold) " vi\\U+00EAn gi\\U+1EEF m\\U+00E3 \\U+0111\\U+00E3 nh\\U+1EDB)."))
        (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+1EA3ng m\\U+00E3 vi\\U+00EAn (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil))
          (sd:table2 pt "B\\U+1EA2NG M\\U+00C3 VI\\U+00CAN"
                     '(("M\\U+00C3 VI\\U+00CAN" 26) ("LO\\U+1EA0I" 32) ("K\\U+00CDCH TH\\U+01AF\\U+1EDAC (mm)" 34) ("SL" 14) ("DT (m\\U+00B2)" 24))
                     trows -1 sc))
        (setq fn (sd:csv-name "_MaVien.csv"))
        (if (setq f (sd:open fn "w"))
          (progn
            (write-line "Ma vien;Ma VL;Loai;Dai (mm);Rong (mm);SL;Tong DT (m2)" f)
            (foreach l (reverse lines) (write-line l f))
            (setq fn (sd:close f))
            (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " fn))))
        (setq fn (sd:csv-name "_MaVienTungVien.csv"))
        (if (setq f (sd:open fn "w"))
          (progn
            (write-line "Ma vien;X tam;Y tam;Ma VL" f)
            (foreach l (reverse pl) (write-line (sd:join (list (car l) (sd:rtos (cadr l) 0) (sd:rtos (caddr l) 0) (cadddr l)) ";") f))
            (setq fn (sd:close f))
            (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " fn)))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDHOBOI - Ho boi: do doc day (dau nong -> dau sau), duong dong muc, khe co gian, mat cat doc, kiem tra theo TCVN 4260:2012 va ISPSC 2015
;;; --------------------------------------------------------------------------
;; Do sau nuoc tai tram s (mm tu thanh nong): phang d1 den a, doc den a+ls, phang d2
(defun sd:hb-depth (s a ls d1 d2)
  (cond ((<= s a) d1)
        ((>= s (+ a ls)) d2)
        (t (+ d1 (* (- s a) (/ (- d2 d1) ls))))))
;; Diem (o + u*s + v*t), v = u xoay +90 do
(defun sd:hb-pt (o u s tt)
  (list (+ (car o) (* (car u) s) (* (- (cadr u)) tt)) (+ (cadr o) (* (cadr u) s) (* (car u) tt)) 0.0))
;; Cac tham so t (da sap xep) noi duong thang tram s0 (vuong goc truc u qua o) cat da giac pts
(defun sd:hb-chord (pts o u s0 / n i p q sp sq f x y ts)
  (setq n (length pts) i 0)
  (repeat n
    (setq p (nth i pts) q (nth (rem (1+ i) n) pts)
          sp (+ (* (- (car p) (car o)) (car u)) (* (- (cadr p) (cadr o)) (cadr u)))
          sq (+ (* (- (car q) (car o)) (car u)) (* (- (cadr q) (cadr o)) (cadr u))))
    (if (and (/= sp sq) (or (and (<= sp s0) (< s0 sq)) (and (<= sq s0) (< s0 sp))))
      (setq f (/ (- s0 sp) (- sq sp))
            x (+ (car p) (* f (- (car q) (car p)))) y (+ (cadr p) (* f (- (cadr q) (cadr p))))
            ts (cons (- (* (- y (cadr o)) (car u)) (* (- x (car o)) (cadr u))) ts)))
    (setq i (1+ i)))
  (vl-sort ts '<))
;; Ve cac doan chord (cap t1-t2, t3-t4...) cua tram s0 tren layer lay
(defun sd:hb-chord-draw (pts o u s0 lay / ts)
  (setq ts (sd:hb-chord pts o u s0))
  (while (>= (length ts) 2)
    (sd:line (sd:hb-pt o u s0 (car ts)) (sd:hb-pt o u s0 (cadr ts)) lay)
    (setq ts (cddr ts)))
  (sd:hb-chord pts o u s0))
;; Kiem tra doc day: i = cao / dai (khong don vi). Tra ve danh sach dong chu
(defun sd:hb-check (d1 d2 i / r)
  (cond ((> i (/ 1.0 3.0))
         (setq r (cons "[!] D\\U+1ED1c \\U+0111\\U+00E1y l\\U+1EDBn h\\U+01A1n 1:3 (33%): v\\U+01B0\\U+1EE3t gi\\U+1EDBi h\\U+1EA1n d\\U+1ED1c v\\U+00F9ng s\\U+00E2u trong ISPSC 2015 \\U+00A7807.1.3." r)))
        ((and (> i (/ 1.0 7.0)) (< d1 838.0))
         (setq r (cons "[!] D\\U+1ED1c \\U+0111\\U+00E1y l\\U+1EDBn h\\U+01A1n 1:7 (14%) ngay t\\U+1EEB v\\U+00F9ng n\\U+01B0\\U+1EDBc n\\U+00F4ng d\\U+01B0\\U+1EDBi 838 mm: v\\U+01B0\\U+1EE3t ISPSC 2015 \\U+00A7807.1.1 (v\\U+00F9ng n\\U+00F4ng t\\U+1ED1i \\U+0111a 1:7; ch\\U+1EC9 \\U+0111\\U+01B0\\U+1EE3c d\\U+1ED1c h\\U+01A1n khi \\U+0111\\U+00E3 qua \\U+0111\\U+1ED9 s\\U+00E2u 838 mm)." r)))
        ((and (> i 0.1) (< d1 1524.0))
         (setq r (cons "[?] D\\U+1ED1c l\\U+1EDBn h\\U+01A1n 1:10 trong v\\U+00F9ng n\\U+01B0\\U+1EDBc s\\U+00E2u \\U+0111\\U+1EBFn 1,5 m: quy \\U+0111\\U+1ECBnh x\\U+00E2y d\\U+1EF1ng M\\U+1EF9 (UpCodes 454.1.2) gi\\U+1EDBi h\\U+1EA1n 1:10 \\U+1EDF v\\U+00F9ng n\\U+00E0y; x\\U+00E1c nh\\U+1EADn ti\\U+00EAu chu\\U+1EA9n \\U+00E1p d\\U+1EE5ng cho d\\U+1EF1 \\U+00E1n." r))))
  (if (or (< d1 838.0) (> d1 1219.0))
    (setq r (cons "[?] \\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u n\\U+00F4ng ngo\\U+00E0i 838 - 1219 mm (ISPSC 2015 \\U+00A7807.2, h\\U+1ED3 gia \\U+0111\\U+00ECnh): \\U+0111\\U+00FAng n\\U+1EBFu l\\U+00E0 b\\U+1EC3 tr\\U+1EBB em / b\\U+1EC3 v\\U+1EA7y ho\\U+1EB7c h\\U+1ED3 c\\U+00F4ng c\\U+1ED9ng; x\\U+00E1c nh\\U+1EADn lo\\U+1EA1i h\\U+1ED3." r)))
  (if (> d2 1200.0)
    (setq r (cons "[i] S\\U+00E2u h\\U+01A1n 1,2 m: TCVN 4260:2012 \\U+00A75.1.8 y\\U+00EAu c\\U+1EA7u b\\U+1EADc \\U+0111\\U+1EE9ng ngh\\U+1EC9 ch\\U+00E2n \\U+1EDF \\U+0111\\U+1ED9 s\\U+00E2u 1,2 m d\\U+1ECDc hai th\\U+00E0nh d\\U+1ECDc; ISPSC 2015 \\U+00A7809.3 y\\U+00EAu c\\U+1EA7u l\\U+1ED1i l\\U+00EAn xu\\U+1ED1ng \\U+1EDF v\\U+00F9ng s\\U+00E2u khi n\\U+01B0\\U+1EDBc s\\U+00E2u qu\\U+00E1 1524 mm." r)))
  (setq r (cons "[i] TCVN 4260:2012 ch\\U+1EC9 quy \\U+0111\\U+1ECBnh \\U+0111\\U+00E1y d\\U+1ED1c v\\U+1EC1 h\\U+1ED1 thu 1 - 3% (\\U+00A75.1.11), kh\\U+00F4ng quy \\U+0111\\U+1ECBnh d\\U+1ED1c t\\U+1EEB \\U+0111\\U+1EA7u n\\U+00F4ng xu\\U+1ED1ng \\U+0111\\U+1EA7u s\\U+00E2u: \\U+0111\\U+1EB7t h\\U+1ED1 thu \\U+1EDF \\U+0111i\\U+1EC3m th\\U+1EA5p nh\\U+1EA5t v\\U+00E0 \\U+0111\\U+1ED1i chi\\U+1EBFu nh\\U+00E0 thi\\U+1EBFt k\\U+1EBF b\\U+1EC3." r))
  (reverse r))

(defun c:SDHOBOI (/ r e pts sp dp u o len smin smax tmin tmax lt a b n ls d1 d2 stp rl lt0 jt dkw dki kh mc pitch i ss pt sc
                    d k nx ny nc v tt lay x ts msg pr rows rh)
  (sd:begin)
  (if (sd:dlg "H\\U+1ED3 b\\U+01A1i: \\U+0111\\U+1ED9 d\\U+1ED1c \\U+0111\\U+00E1y, \\U+0111\\U+1ED3ng m\\U+1EE9c, khe co gi\\U+00E3n, m\\U+1EB7t c\\U+1EAFt (SDHOBOI)"
              (list (list "d1" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u n\\U+00F4ng (mm)" 'real (sd:cfg "HB-D1" 1000.0))
                    (list "d2" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u s\\U+00E2u (mm)" 'real (sd:cfg "HB-D2" 1500.0))
                    (list "a" "\\U+0110o\\U+1EA1n \\U+0111\\U+00E1y ph\\U+1EB3ng \\U+0111\\U+1EA7u n\\U+00F4ng (mm, t\\U+00EDnh t\\U+1EEB th\\U+00E0nh n\\U+00F4ng)" 'real0 (sd:cfg "HB-A" 1000.0))
                    (list "b" "\\U+0110o\\U+1EA1n \\U+0111\\U+00E1y ph\\U+1EB3ng \\U+0111\\U+1EA7u s\\U+00E2u (mm; 0 = d\\U+1ED1c \\U+0111\\U+1EBFn h\\U+1EBFt h\\U+1ED3)" 'real0 (sd:cfg "HB-B" 0.0))
                    (list "n" "Ho\\U+1EB7c nh\\U+1EADp \\U+0111\\U+1ED9 d\\U+1ED1c 1:n (0 = suy t\\U+1EEB \\U+0111o\\U+1EA1n ph\\U+1EB3ng; nh\\U+1EADp n th\\U+00EC \\U+0111o\\U+1EA1n ph\\U+1EB3ng \\U+0111\\U+1EA7u s\\U+00E2u t\\U+1EF1 t\\U+00EDnh)" 'real0 (sd:cfg "HB-N" 0.0))
                    (list "stp" "B\\U+01B0\\U+1EDBc \\U+0111\\U+01B0\\U+1EDDng \\U+0111\\U+1ED3ng m\\U+1EE9c \\U+0111\\U+00E1y (mm \\U+0111\\U+1ED9 s\\U+00E2u)" 'real (sd:cfg "HB-STEP" 100.0))
                    (list "rl" "Cao \\U+0111\\U+1ED9 m\\U+1EB7t n\\U+01B0\\U+1EDBc (m so v\\U+1EDBi \\U+00B10.000)" 'real0 (sd:cfg "HB-RL" 0.0))
                    (list "lt" "Chi\\U+1EC1u d\\U+00E0i vi\\U+00EAn \\U+0111\\U+00E1 l\\U+00E1t theo h\\U+01B0\\U+1EDBng d\\U+1ED1c (mm; 0 = b\\U+1ECF qua)" 'real0 (sd:cfg "HB-LT" 600.0))
                    (list "jt" "Ron (mm)" 'real0 (sd:cfg "HB-JT" 3.0))
                    (list "dkw" "B\\U+1EC1 r\\U+1ED9ng s\\U+00E2n quanh h\\U+1ED3 (mm; 0 = b\\U+1ECF qua)" 'real0 (sd:cfg "HB-DKW" 3000.0))
                    (list "dki" "\\U+0110\\U+1ED9 d\\U+1ED1c s\\U+00E2n (%)" 'real (sd:cfg "HB-DKI" 1.5))
                    (list "kh" "Khe co gi\\U+00E3n: kho\\U+1EA3ng c\\U+00E1ch t\\U+1ED1i \\U+0111a (mm; 0 = kh\\U+00F4ng v\\U+1EBD)" 'real0 (sd:cfg "HB-KH" 3000.0))
                    (list "mc" "V\\U+1EBD m\\U+1EB7t c\\U+1EAFt d\\U+1ECDc v\\U+00E0 b\\U+1EA3ng cao \\U+0111\\U+1ED9 \\U+0111\\U+00E1y" 'tog t)))
    (progn
      (setq d1 (sd:cfg-put "HB-D1" (sd:v "d1")) d2 (sd:cfg-put "HB-D2" (sd:v "d2")) a (sd:cfg-put "HB-A" (cond ((sd:v "a")) (0.0)))
            b (sd:cfg-put "HB-B" (cond ((sd:v "b")) (0.0))) n (sd:cfg-put "HB-N" (cond ((sd:v "n")) (0.0)))
            stp (sd:cfg-put "HB-STEP" (sd:v "stp")) rl (sd:cfg-put "HB-RL" (cond ((sd:v "rl")) (0.0)))
            lt0 (sd:cfg-put "HB-LT" (cond ((sd:v "lt")) (0.0))) jt (sd:cfg-put "HB-JT" (cond ((sd:v "jt")) (0.0)))
            dkw (sd:cfg-put "HB-DKW" (cond ((sd:v "dkw")) (0.0))) dki (sd:cfg-put "HB-DKI" (sd:v "dki"))
            kh (sd:cfg-put "HB-KH" (cond ((sd:v "kh")) (0.0))) mc (sd:v "mc") sc (sd:sc))
      (cond
        ((<= d2 d1) (princ "\n[SD] \\U+0110\\U+1ED9 s\\U+00E2u \\U+0111\\U+1EA7u s\\U+00E2u ph\\U+1EA3i l\\U+1EDBn h\\U+01A1n \\U+0111\\U+1EA7u n\\U+00F4ng."))
        ((null (setq r (entsel "\nCh\\U+1ECDn polyline k\\U+00EDn l\\U+00E0 m\\U+00E9p trong h\\U+1ED3 (m\\U+1EB7t b\\U+1EB1ng l\\U+00F2ng h\\U+1ED3): ")))
         (princ "\n[SD] Ch\\U+01B0a ch\\U+1ECDn."))
        ((not (and (= (cdr (assoc 0 (entget (car r)))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget (car r))))))))
         (princ "\n[SD] C\\U+1EA7n ch\\U+1ECDn polyline k\\U+00EDn."))
        ((null (setq sp (sd:getpt "\nB\\U+1EA5m m\\U+1ED9t \\U+0111i\\U+1EC3m \\U+1EDF \\U+0111\\U+1EA7u N\\U+00D4NG (tr\\U+00EAn tr\\U+1EE5c d\\U+1ED1c): " nil))) (princ "\n[SD] Ch\\U+01B0a ch\\U+1ECDn \\U+0111i\\U+1EC3m."))
        ((null (setq dp (sd:getpt "\nB\\U+1EA5m m\\U+1ED9t \\U+0111i\\U+1EC3m \\U+1EDF \\U+0111\\U+1EA7u S\\U+00C2U (h\\U+01B0\\U+1EDBng d\\U+1ED1c xu\\U+1ED1ng): " sp))) (princ "\n[SD] Ch\\U+01B0a ch\\U+1ECDn \\U+0111i\\U+1EC3m."))
        (t
         (setq e (car r) pts (sd:curve-pts e) o (sd:2d sp) len (distance (sd:2d sp) (sd:2d dp)))
         (if (< len 1.0)
           (princ "\n[SD] Hai \\U+0111i\\U+1EC3m tr\\U+00F9ng nhau.")
           (progn
             (setq u (list (/ (- (car dp) (car sp)) len) (/ (- (cadr dp) (cadr sp)) len))
                   ss (mapcar '(lambda (q) (+ (* (- (car q) (car o)) (car u)) (* (- (cadr q) (cadr o)) (cadr u)))) pts)
                   tt (mapcar '(lambda (q) (- (* (- (cadr q) (cadr o)) (car u)) (* (- (car q) (car o)) (cadr u)))) pts)
                   smin (apply 'min ss) smax (apply 'max ss) tmin (apply 'min tt) tmax (apply 'max tt) lt (- smax smin))
             (cond
               ((> n 0.0) (setq ls (* (- d2 d1) n) b (- lt a ls)))
               (t (setq ls (- lt a b))))
             (cond
               ((or (<= ls 1.0) (< b -1e-6))
                (princ (strcat "\n[SD] H\\U+1ED3 d\\U+00E0i " (sd:num lt) " mm theo tr\\U+1EE5c kh\\U+00F4ng \\U+0111\\U+1EE7 ch\\U+1ED7 cho \\U+0111o\\U+1EA1n ph\\U+1EB3ng + \\U+0111o\\U+1EA1n d\\U+1ED1c: gi\\U+1EA3m \\U+0111o\\U+1EA1n ph\\U+1EB3ng ho\\U+1EB7c t\\U+0103ng \\U+0111\\U+1ED9 d\\U+1ED1c.")))
               (t
                (setq i (/ (- d2 d1) ls) pitch (+ lt0 jt))
                (foreach lay (list (list "SD-HOBOI" 5) (list "SD-HOBOI-DM" 8) (list "SD-HOBOI-DOI" 1) (list "SD-HOBOI-KHE" 2) (list "SD-HOBOI-MC" 4))
                  (sd:make-layer (car lay) (cadr lay) "Continuous" 18))
                ;; truc doc + nhan
                (sd:line (sd:hb-pt o u smin (/ (+ tmin tmax) 2.0)) (sd:hb-pt o u smax (/ (+ tmin tmax) 2.0)) "SD-HOBOI")
                (sd:text (sd:p+ (sd:hb-pt o u smin (/ (+ tmin tmax) 2.0)) 0 (* 3.0 sc)) (strcat "\\U+0110\\U+1EA6U N\\U+00D4NG " (sd:num d1)) (* 2.5 sc) "L" "SD-HOBOI")
                (sd:text (sd:p+ (sd:hb-pt o u smax (/ (+ tmin tmax) 2.0)) 0 (* 3.0 sc)) (strcat "\\U+0110\\U+1EA6U S\\U+00C2U " (sd:num d2)) (* 2.5 sc) "R" "SD-HOBOI")
                ;; duong doi doc
                (if (> a 1.0) (sd:hb-chord-draw pts o u (+ smin a) "SD-HOBOI-DOI"))
                (if (> b 1.0) (sd:hb-chord-draw pts o u (+ smin a ls) "SD-HOBOI-DOI"))
                ;; duong dong muc
                (setq k 1 nc 0)
                (while (< (+ d1 (* k stp)) (- d2 1e-6))
                  (setq d (+ d1 (* k stp)) x (+ smin a (/ (- d d1) i)) ts (sd:hb-chord-draw pts o u x "SD-HOBOI-DM"))
                  (if ts
                    (sd:text (sd:hb-pt o u x (+ (car ts) (* 2.0 sc))) (strcat "-" (sd:num d) " (" (sd:rtos (- rl (/ d 1000.0)) 2) ")") (* 2.0 sc) "L" "SD-HOBOI-DM"))
                  (setq k (1+ k) nc (1+ nc)))
                ;; khe co gian
                (setq pr nil)
                (if (> kh 0.0)
                  (progn
                    (setq nx (max 1 (fix (+ 0.999 (/ lt kh)))) ny (max 1 (fix (+ 0.999 (/ (- tmax tmin) kh)))))
                    (setq k 1)
                    (repeat (1- nx) (sd:hb-chord-draw pts o u (+ smin (* k (/ lt nx))) "SD-HOBOI-KHE") (setq k (1+ k)))
                    (setq k 1 v (list (- (cadr u)) (car u)))
                    (repeat (1- ny)
                      (sd:hb-chord-draw pts o v (+ tmin (* k (/ (- tmax tmin) ny))) "SD-HOBOI-KHE")
                      (setq k (1+ k)))
                    (setq pr (list (/ lt nx) (/ (- tmax tmin) ny)))))
                ;; bao cao
                (princ (strcat "\n[SD] SDHOBOI: h\\U+1ED3 d\\U+00E0i " (sd:num lt) " mm theo tr\\U+1EE5c, r\\U+1ED9ng " (sd:num (- tmax tmin)) " mm."
                               "\n  D\\U+1ED1c \\U+0111\\U+00E1y " (sd:rtos (* 100.0 i) 2) "% = 1:" (sd:rtos (/ 1.0 i) 1) " tr\\U+00EAn \\U+0111o\\U+1EA1n d\\U+1ED1c d\\U+00E0i " (sd:num ls) " mm (ph\\U+1EB3ng " (sd:num a) " + d\\U+1ED1c + ph\\U+1EB3ng " (sd:num b) ")."
                               "\n  S\\U+1ED1 \\U+0111\\U+01B0\\U+1EDDng \\U+0111\\U+1ED3ng m\\U+1EE9c \\U+0111\\U+00E1y: " (itoa nc) " (b\\U+01B0\\U+1EDBc " (sd:num stp) " mm)."))
                (if (> lt0 0.0)
                  (princ (strcat "\n  M\\U+1ED7i vi\\U+00EAn " (sd:num lt0) " mm (ron " (sd:num jt) ") theo h\\U+01B0\\U+1EDBng d\\U+1ED1c ch\\U+00EAnh cao " (sd:rtos (* i lt0) 1) " mm gi\\U+1EEFa hai m\\U+1EA1ch."
                                 "\n  \\U+0110\\U+01B0\\U+1EDDng \\U+0111\\U+1ED5i d\\U+1ED1c 1 (s=" (sd:num a) ") r\\U+01A1i v\\U+00E0o " (sd:rtos (/ a pitch) 2) " b\\U+01B0\\U+1EDBc vi\\U+00EAn; \\U+0111\\U+1EC1 xu\\U+1EA5t \\U+0111\\U+1EB7t \\U+0111\\U+00FAng m\\U+1EA1ch: s = " (sd:num (* pitch (fix (+ 0.5 (/ a pitch))))) " mm."
                                 (if (> b 1.0) (strcat "\n  \\U+0110\\U+01B0\\U+1EDDng \\U+0111\\U+1ED5i d\\U+1ED1c 2 (s=" (sd:num (+ a ls)) ") r\\U+01A1i v\\U+00E0o " (sd:rtos (/ (+ a ls) pitch) 2) " b\\U+01B0\\U+1EDBc vi\\U+00EAn.") ""))))
                (if pr
                  (princ (strcat "\n  Khe co gi\\U+00E3n: " (itoa nx) " \\U+00F4 theo tr\\U+1EE5c (" (sd:num (car pr)) " mm), " (itoa ny) " \\U+00F4 ngang (" (sd:num (cadr pr)) " mm). B\\U+1EC1 r\\U+1ED9ng khe t\\U+1ED1i thi\\U+1EC3u "
                                 (if (<= (max (car pr) (cadr pr)) 2600.0) "9" "12") " mm, s\\U+00E2u \\U+00EDt nh\\U+1EA5t b\\U+1EB1ng n\\U+1EEDa b\\U+1EC1 r\\U+1ED9ng, tr\\U+00E1m silicone / urethane c\\U+00F3 backer rod (Laticrete / TCNA EJ171: 2,4 - 3,7 m m\\U+1ED7i ph\\U+01B0\\U+01A1ng v\\U+00E0 s\\U+00E1t m\\U+1ECDi m\\U+1EB7t ch\\U+1EB7n)."
                                 (if (> (max (car pr) (cadr pr)) 3700.0) "\n  [!] Kho\\U+1EA3ng c\\U+00E1ch khe v\\U+01B0\\U+1EE3t 3,7 m: gi\\U+1EA3m s\\U+1ED1 mm kho\\U+1EA3ng c\\U+00E1ch t\\U+1ED1i \\U+0111a." ""))))
                (if (> dkw 0.0)
                  (princ (strcat "\n  S\\U+00E2n r\\U+1ED9ng " (sd:num dkw) " mm d\\U+1ED1c " (sd:rtos dki 2) "%: ch\\U+00EAnh cao hai m\\U+00E9p s\\U+00E2n " (sd:rtos (* dkw (/ dki 100.0)) 1) " mm; v\\U+1EEFa t\\U+1EA1o d\\U+1ED1c d\\U+00E0y th\\U+00EAm \\U+0111\\U+00FAng s\\U+1ED1 n\\U+00E0y \\U+1EDF m\\U+00E9p th\\U+1EA5p."
                                 (if (or (< dki 1.0) (> dki 2.0)) "\n  [!] D\\U+1ED1c s\\U+00E2n ngo\\U+00E0i 1 - 2%: TCVN 4260:2012 \\U+00A76.2.24 l\\U+1EA5y 1 - 2% v\\U+1EC1 ph\\U+00EDa ph\\U+1EC5u thu." ""))))
                (foreach msg (sd:hb-check d1 d2 i) (princ (strcat "\n  " msg)))
                ;; mat cat doc + bang cao do
                (if (and mc (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n m\\U+1EB7t c\\U+1EAFt d\\U+1ECDc <b\\U+1ECF qua>: " nil)))
                  (progn
                    (setq pt (sd:2d pt))
                    (sd:line (sd:p+ pt (- 300.0) 0.0) (sd:p+ pt (+ lt 300.0) 0.0) "SD-HOBOI-MC")
                    (sd:text (sd:p+ pt (+ lt 300.0) (* 1.0 sc)) (strcat "M\\U+1EF0C N\\U+01AF\\U+1EDAC " (sd:rtos rl 2)) (* 2.5 sc) "L" "SD-HOBOI-MC")
                    (sd:line (sd:p+ pt 0 (* 8.0 sc)) (sd:p+ pt 0 (- d1)) "SD-HOBOI-MC")
                    (sd:line (sd:p+ pt lt (* 8.0 sc)) (sd:p+ pt lt (- d2)) "SD-HOBOI-MC")
                    (sd:pline (list (sd:p+ pt 0 (- d1)) (sd:p+ pt a (- d1)) (sd:p+ pt (+ a ls) (- d2)) (sd:p+ pt lt (- d2))) nil "SD-HOBOI-MC")
                    (sd:text (sd:p+ pt (/ a 2.0) (- (+ d1 (* 4.0 sc)))) (strcat "-" (sd:num d1)) (* 2.5 sc) "MC" "SD-HOBOI-MC")
                    (sd:text (sd:p+ pt (- lt (/ (max b 1.0) 2.0)) (- (+ d2 (* 4.0 sc)))) (strcat "-" (sd:num d2)) (* 2.5 sc) "MC" "SD-HOBOI-MC")
                    (sd:text (sd:p+ pt (+ a (/ ls 2.0)) (- (+ (/ (+ d1 d2) 2.0) (* 6.0 sc)))) (strcat "i = " (sd:rtos (* 100.0 i) 2) "% (1:" (sd:rtos (/ 1.0 i) 1) ")") (* 3.0 sc) "MC" "SD-HOBOI-MC")
                    (sd:text (sd:p+ pt (/ lt 2.0) (* 10.0 sc)) (strcat "M\\U+1EB6T C\\U+1EAET D\\U+1ECCC H\\U+1ED2 B\\U+01A0I (\\U+0111\\U+1EA7u n\\U+00F4ng \\U+2192 \\U+0111\\U+1EA7u s\\U+00E2u), " (sd:num lt) " mm") (* 4.0 sc) "MC" "SD-HOBOI-MC")
                    (if (> pitch 0.0)
                      (progn
                        (setq rows 0 x 0.0 rh (* 4.0 sc))
                        (sd:text (sd:p+ pt 0 (- (+ d2 (* 14.0 sc)))) "B\\U+1EA2NG CAO \\U+0110\\U+1ED8 \\U+0110\\U+00C1Y T\\U+1EA0I M\\U+1EA0CH VI\\U+00CAN (t\\U+1EEB th\\U+00E0nh n\\U+00F4ng: \\U+0111\\U+1ED9 s\\U+00E2u / cao \\U+0111\\U+1ED9 ho\\U+00E0n thi\\U+1EC7n)" (* 2.5 sc) "L" "SD-HOBOI-MC")
                        (while (and (<= x (+ lt 1e-6)) (< rows 60))
                          (sd:text (sd:p+ pt 0 (- (+ d2 (* 14.0 sc) (* (1+ rows) rh)))) (strcat "s=" (sd:num x) "   -" (sd:num (sd:hb-depth x a ls d1 d2)) "   (" (sd:rtos (- rl (/ (sd:hb-depth x a ls d1 d2) 1000.0)) 3) ")") (* 2.0 sc) "L" "SD-HOBOI-MC")
                          (setq x (+ x pitch) rows (1+ rows)))
                        (if (<= x (+ lt 1e-6)) (princ "\n[SD] B\\U+1EA3ng cao \\U+0111\\U+1ED9 ch\\U+1EC9 li\\U+1EC7t k\\U+00EA 60 m\\U+1EA1ch \\U+0111\\U+1EA7u."))))))))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDLIENCAODO - Chuoi cao do: san chinh -> san WC -> san ho -> muc nuoc -> day ho; pheu thu tung vung, chenh cao, doi chieu doc
;;; --------------------------------------------------------------------------
;; Chon vung (polyline kin) + cac pheu thu; tra (khoang-cach-xa-nhat-mm pheu pts) hoac nil
(defun sd:lc-zone (name / r pts drs p step far)
  (cond
    ((null (setq r (entsel (strcat "\nCh\\U+1ECDn polyline k\\U+00EDn v\\U+00F9ng " name " <b\\U+1ECF qua>: "))))
     nil)
    ((not (and (= (cdr (assoc 0 (entget (car r)))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget (car r))))))))
     (princ "\n[SD] C\\U+1EA7n polyline k\\U+00EDn: b\\U+1ECF v\\U+00F9ng n\\U+00E0y.") nil)
    (t
     (setq pts (sd:curve-pts (car r)))
     (while (setq p (getpoint (strcat "\nCh\\U+1ECDn ph\\U+1EC5u thu c\\U+1EE7a v\\U+00F9ng " name " <Enter xong>: ")))
       (setq drs (cons (sd:2d p) drs)))
     (cond
       ((null drs) (princ "\n[SD] Ch\\U+01B0a ch\\U+1ECDn ph\\U+1EC5u thu: b\\U+1ECF v\\U+00F9ng n\\U+00E0y.") nil)
       (t (setq step (max 100.0 (/ (distance (car (sd:bbox pts)) (cadr (sd:bbox pts))) 40.0))
                far (sd:dr-far pts drs step))
          (list (car far) drs pts))))))
;; Dong chu cao do (m) co dau: +0.000 / -0.045
(defun sd:lc-rl (x) (strcat (if (>= x -0.0005) "+" "") (sd:rtos x 3)))
;; Cac canh bao cua chuoi cao do. m = cao do san chinh, bc = ha cot WC (mm), iw / id = doc WC / san ho (%), wl = muc nuoc, dk = cao do san ho tai mep ho (m)
(defun sd:lc-check (m bc iw id wl dk / r)
  (if (<= bc 0.0) (setq r (cons "[!] S\\U+00E0n WC kh\\U+00F4ng th\\U+1EA5p h\\U+01A1n s\\U+00E0n ch\\U+00EDnh t\\U+1EA1i ng\\U+01B0\\U+1EE1ng c\\U+1EEDa: n\\U+01B0\\U+1EDBc d\\U+1EC5 ch\\U+1EA3y ra s\\U+00E0n ch\\U+00EDnh; th\\U+00F4ng th\\U+01B0\\U+1EDDng h\\U+1EA1 c\\U+1ED1t s\\U+00E0n WC (nh\\U+1EADp theo thi\\U+1EBFt k\\U+1EBF)." r)))
  (if (and iw (or (< iw 1.0) (> iw 2.0))) (setq r (cons "[?] D\\U+1ED1c s\\U+00E0n WC ngo\\U+00E0i 1 - 2%: TCVN 4260:2012 \\U+00A76.2.24 l\\U+1EA5y 1 - 2% v\\U+1EC1 ph\\U+00EDa ph\\U+1EC5u thu (cho s\\U+00E2n quanh b\\U+1EC3 v\\U+00E0 s\\U+00E0n khu v\\U+1EC7 sinh c\\U+1EE7a b\\U+1EC3 b\\U+01A1i)." r)))
  (if (and id (or (< id 1.0) (> id 2.0))) (setq r (cons "[?] D\\U+1ED1c s\\U+00E2n h\\U+1ED3 ngo\\U+00E0i 1 - 2%: TCVN 4260:2012 \\U+00A76.2.24." r)))
  (if (and wl dk (> wl dk)) (setq r (cons "[!] M\\U+1EF1c n\\U+01B0\\U+1EDBc cao h\\U+01A1n m\\U+1EB7t s\\U+00E2n t\\U+1EA1i m\\U+00E9p h\\U+1ED3: n\\U+01B0\\U+1EDBc tr\\U+00E0n ra s\\U+00E2n." r)))
  (if (and dk (> dk (+ m 0.0005))) (setq r (cons "[?] S\\U+00E2n h\\U+1ED3 t\\U+1EA1i m\\U+00E9p h\\U+1ED3 cao h\\U+01A1n s\\U+00E0n ch\\U+00EDnh: ki\\U+1EC3m tra n\\U+01B0\\U+1EDBc m\\U+01B0a / n\\U+01B0\\U+1EDBc r\\U+1EEDa s\\U+00E2n c\\U+00F3 ch\\U+1EA3y v\\U+00E0o nh\\U+00E0 kh\\U+00F4ng." r)))
  (reverse r))

(defun c:SDLIENCAODO (/ m bc iw id dk wl d1 d2 wc dkz levels n pt sc rowh y x0 x1 i lv prev dr bh ds)
  (sd:begin)
  (if (sd:dlg "Chu\\U+1ED7i cao \\U+0111\\U+1ED9: s\\U+00E0n ch\\U+00EDnh, WC, s\\U+00E2n h\\U+1ED3, \\U+0111\\U+00E1y h\\U+1ED3 (SDLIENCAODO)"
              (list (list "m" "Cao \\U+0111\\U+1ED9 s\\U+00E0n ch\\U+00EDnh ho\\U+00E0n thi\\U+1EC7n (m so v\\U+1EDBi \\U+00B10.000)" 'real0 (sd:cfg "LC-M" 0.0))
                    (list "bc" "S\\U+00E0n WC h\\U+1EA1 so v\\U+1EDBi s\\U+00E0n ch\\U+00EDnh t\\U+1EA1i ng\\U+01B0\\U+1EE1ng c\\U+1EEDa (mm)" 'real0 (sd:cfg "LC-BC" 20.0))
                    (list "iw" "D\\U+1ED1c s\\U+00E0n WC v\\U+1EC1 ph\\U+1EC5u thu (%)" 'real (sd:cfg "LC-IW" 1.0))
                    (list "dk" "Cao \\U+0111\\U+1ED9 s\\U+00E2n h\\U+1ED3 t\\U+1EA1i m\\U+00E9p h\\U+1ED3 (m)" 'real0 (sd:cfg "LC-DK" (sd:cfg "LC-M" 0.0)))
                    (list "id" "D\\U+1ED1c s\\U+00E2n h\\U+1ED3 v\\U+1EC1 ph\\U+1EC5u / r\\U+00E3nh thu (%)" 'real (sd:cfg "LC-ID" 1.5))
                    (list "wl" "Cao \\U+0111\\U+1ED9 m\\U+1EF1c n\\U+01B0\\U+1EDBc h\\U+1ED3 (m; h\\U+1ED3 \\U+0111\\U+00E3 nh\\U+1EADp b\\U+1EB1ng SDHOBOI th\\U+00EC l\\U+1EA5y theo \\U+0111\\U+00F3)" 'real0 (sd:cfg "HB-RL" -0.05))
                    (list "d1" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u n\\U+00F4ng (mm)" 'real (sd:cfg "HB-D1" 1000.0))
                    (list "d2" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u s\\U+00E2u (mm)" 'real (sd:cfg "HB-D2" 1500.0))
                    (list "bh" "B\\U+1EC1 r\\U+1ED9ng h\\U+1ED3 \\U+1EDF m\\U+1EB7t c\\U+1EAFt ngang (mm; ch\\U+1EC9 \\U+0111\\U+1EC3 v\\U+1EBD m\\U+1EB7t c\\U+1EAFt)" 'real0 (sd:cfg "LC-BH" 3000.0))
                    (list "ds" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc t\\U+1EA1i m\\U+1EB7t c\\U+1EAFt ngang (mm; 0 = \\U+0111\\U+1EA7u n\\U+00F4ng)" 'real0 (sd:cfg "LC-DS" 0.0))))
    (progn
      (setq m (sd:cfg-put "LC-M" (cond ((sd:v "m")) (0.0))) bc (sd:cfg-put "LC-BC" (cond ((sd:v "bc")) (0.0)))
            iw (sd:cfg-put "LC-IW" (sd:v "iw")) dk (sd:cfg-put "LC-DK" (cond ((sd:v "dk")) (0.0)))
            id (sd:cfg-put "LC-ID" (sd:v "id")) wl (sd:cfg-put "HB-RL" (cond ((sd:v "wl")) (0.0)))
            d1 (sd:cfg-put "HB-D1" (sd:v "d1")) d2 (sd:cfg-put "HB-D2" (sd:v "d2")) sc (sd:sc)
            bh (sd:cfg-put "LC-BH" (cond ((sd:v "bh")) (3000.0))) ds (sd:cfg-put "LC-DS" (cond ((sd:v "ds")) (0.0))))
      (if (<= ds 0.0) (setq ds d1))
      (sd:ho-warn '("LC-M" "LC-BC" "LC-IW" "LC-ID" "LC-DK" "HB-RL" "HB-D1" "HB-D2"))
      (princ "\nV\\U+00F9ng s\\U+00E0n WC (m\\U+1ED7i l\\U+1EA7n m\\U+1ED9t v\\U+00F9ng; Enter \\U+0111\\U+1EC3 b\\U+1ECF qua):")
      (setq wc (sd:lc-zone "WC"))
      (princ "\nV\\U+00F9ng s\\U+00E2n h\\U+1ED3:")
      (setq dkz (sd:lc-zone "s\\U+00E2n h\\U+1ED3"))
      ;; danh sach cao do (nhan rl), cao truoc
      (setq levels (list (list "S\\U+00E0n ch\\U+00EDnh ho\\U+00E0n thi\\U+1EC7n" m)
                         (list "S\\U+00E2n h\\U+1ED3 t\\U+1EA1i m\\U+00E9p h\\U+1ED3" dk)
                         (list "M\\U+1EF1c n\\U+01B0\\U+1EDBc h\\U+1ED3" wl)
                         (list "\\U+0110\\U+00E1y h\\U+1ED3 \\U+0111\\U+1EA7u n\\U+00F4ng" (- wl (/ d1 1000.0)))
                         (list "\\U+0110\\U+00E1y h\\U+1ED3 \\U+0111\\U+1EA7u s\\U+00E2u (h\\U+1ED1 thu \\U+0111\\U+00E1y h\\U+1ED3)" (- wl (/ d2 1000.0))))
            n (- m (/ bc 1000.0)))
      (setq levels (cons (list "S\\U+00E0n WC t\\U+1EA1i ng\\U+01B0\\U+1EE1ng c\\U+1EEDa (\\U+0111i\\U+1EC3m cao nh\\U+1EA5t)" n) levels))
      (if wc
        (setq levels (cons (list (strcat "S\\U+00E0n WC t\\U+1EA1i ph\\U+1EC5u thu (xa ph\\U+1EC5u nh\\U+1EA5t " (sd:rtos (/ (car wc) 1000.0) 2) " m)") (- n (* (/ iw 100.0) (/ (car wc) 1000.0)))) levels)))
      (if dkz
        (setq levels (cons (list (strcat "S\\U+00E2n h\\U+1ED3 t\\U+1EA1i ph\\U+1EC5u / r\\U+00E3nh thu (xa nh\\U+1EA5t " (sd:rtos (/ (car dkz) 1000.0) 2) " m)") (- dk (* (/ id 100.0) (/ (car dkz) 1000.0)))) levels)))
      (setq levels (sd:sort levels '(lambda (a b) (> (cadr a) (cadr b)))))
      (princ "\n[SD] SDLIENCAODO: chu\\U+1ED7i cao \\U+0111\\U+1ED9 t\\U+1EEB cao xu\\U+1ED1ng th\\U+1EA5p")
      (setq prev nil)
      (foreach lv levels
        (princ (strcat "\n  " (sd:lc-rl (cadr lv)) "  " (car lv) (if prev (strcat "   (th\\U+1EA5p h\\U+01A1n m\\U+1EE9c tr\\U+00EAn " (sd:rtos (* 1000.0 (- prev (cadr lv))) 0) " mm)") "")))
        (setq prev (cadr lv)))
      (princ (strcat "\n  S\\U+00E0n WC t\\U+1EA1i ng\\U+01B0\\U+1EE1ng th\\U+1EA5p h\\U+01A1n s\\U+00E0n ch\\U+00EDnh " (sd:rtos bc 0) " mm"
                     (if wc (strcat "; t\\U+1EA1i ph\\U+1EC5u th\\U+1EA5p h\\U+01A1n s\\U+00E0n ch\\U+00EDnh " (sd:rtos (* 1000.0 (- m (- n (* (/ iw 100.0) (/ (car wc) 1000.0))))) 0) " mm") "")
                     "; s\\U+00E2n h\\U+1ED3 c\\U+00E1ch m\\U+1EF1c n\\U+01B0\\U+1EDBc " (sd:rtos (* 1000.0 (- dk wl)) 0) " mm."))
      (foreach msg (sd:lc-check m bc (if wc iw) (if dkz id) wl dk) (princ (strcat "\n  " msg)))
      (vlax-ldata-put "SD" "LC-LEVELS" (mapcar '(lambda (lv) (list (car lv) (cadr lv))) levels))
      (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n s\\U+01A1 \\U+0111\\U+1ED3 cao \\U+0111\\U+1ED9 <b\\U+1ECF qua>: " nil))
        (progn
          (sd:make-layer "SD-CAODO-LIEN" 5 "Continuous" 18)
          (setq pt (sd:2d pt) rowh (* 14.0 sc) x0 0.0 x1 (* 60.0 sc) i 0 prev nil)
          (sd:text (sd:p+ pt 0 (* 8.0 sc)) "S\\U+01A0 \\U+0110\\U+1ED2 LI\\U+00CAN H\\U+1EC6 CAO \\U+0110\\U+1ED8 (kh\\U+00F4ng theo t\\U+1EC9 l\\U+1EC7 \\U+0111\\U+1EE9ng)" (* 4.0 sc) "L" "SD-CAODO-LIEN")
          (foreach lv levels
            (setq y (- (* i rowh)))
            (sd:line (sd:p+ pt x0 y) (sd:p+ pt x1 y) "SD-CAODO-LIEN")
            (sd:text (sd:p+ pt (- x0 (* 2.0 sc)) y) (sd:lc-rl (cadr lv)) (* 2.5 sc) "MR" "SD-CAODO-LIEN")
            (sd:text (sd:p+ pt (+ x1 (* 2.0 sc)) y) (car lv) (* 2.5 sc) "ML" "SD-CAODO-LIEN")
            (if prev
              (sd:text (sd:p+ pt (/ x1 2.0) (+ y (/ rowh 2.0))) (strcat "\\U+0394 " (sd:rtos (* 1000.0 (- prev (cadr lv))) 0) " mm") (* 2.0 sc) "MC" "SD-CAODO-LIEN"))
            (setq prev (cadr lv) i (1+ i)))))
      (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n m\\U+1EB7t c\\U+1EAFt ngang \\U+0111\\U+00FAng t\\U+1EC9 l\\U+1EC7 (g\\U+1ED1c = cao \\U+0111\\U+1ED9 \\U+00B10.000) <b\\U+1ECF qua>: " nil))
        (sd:lc-section (sd:2d pt) m n (if wc (- n (* (/ iw 100.0) (/ (car wc) 1000.0)))) (if wc (car wc))
                       dk (if dkz (- dk (* (/ id 100.0) (/ (car dkz) 1000.0)))) (if dkz (car dkz)) wl ds bh sc))))
  (sd:finish))

;; Mat cat ngang dung ti le (1 don vi = 1 mm ca ngang lan dung): san chinh -> nguong -> san WC doc ve pheu; mep ho: thanh ho, day ho, san ho doc ra xa ho
;; m, n, nw = cao do san chinh / WC tai nguong / WC tai pheu (m); lw, ld = khoang xa nhat (mm); dk, dd = san ho tai mep / tai pheu (m)
(defun sd:lc-section (pt m n nw lw dk dd ld wl ds bh sc / lay x1 x2 xb fl wl2 lwd ldd)
  (setq lay (sd:make-layer "SD-CAODO-MC" 3 "Continuous" 25) lwd (cond (lw) (1500.0)) ldd (cond (ld) (1500.0))
        x1 1000.0 x2 (+ x1 lwd) xb (+ x2 1500.0 bh 300.0) fl (- wl (/ ds 1000.0)))
  (sd:text (sd:p+ pt 0 (+ (* 1000.0 m) (* 14.0 sc))) "M\\U+1EB6T C\\U+1EAET NGANG CAO \\U+0110\\U+1ED8 (\\U+0111\\U+00FAng t\\U+1EC9 l\\U+1EC7 1:1 theo mm, g\\U+1ED1c \\U+00B10.000)" (* 4.0 sc) "L" lay)
  ;; san chinh + nguong + san WC
  (sd:pline (list (sd:p+ pt 0 (* 1000.0 m)) (sd:p+ pt x1 (* 1000.0 m)) (sd:p+ pt x1 (* 1000.0 n)) (sd:p+ pt x2 (* 1000.0 (cond (nw) (n))))) nil lay)
  (sd:text (sd:p+ pt (/ x1 2.0) (+ (* 1000.0 m) (* 3.0 sc))) (strcat "S\\U+00C0N CH\\U+00CDNH " (sd:lc-rl m)) (* 2.5 sc) "MC" lay)
  (sd:text (sd:p+ pt (+ x1 (* 2.0 sc)) (- (* 1000.0 n) (* 5.0 sc))) (strcat "NG\\U+01AF\\U+1EE0NG WC " (sd:lc-rl n)) (* 2.5 sc) "L" lay)
  (if nw (sd:text (sd:p+ pt x2 (- (* 1000.0 nw) (* 6.0 sc))) (strcat "PH\\U+1EC4U THU WC " (sd:lc-rl nw)) (* 2.5 sc) "MR" lay))
  (sd:text (sd:p+ pt (+ x1 (* 2.0 sc)) (+ (* 1000.0 n) (* 4.0 sc))) (strcat "h\\U+1EA1 " (sd:rtos (* 1000.0 (- m n)) 0) " mm") (* 2.0 sc) "L" lay)
  ;; ho: san ho trai, thanh ho, day ho, thanh ho, san ho doc ra xa phia phai
  (setq wl2 (+ x2 1500.0))
  (sd:pline (list (sd:p+ pt wl2 (* 1000.0 dk)) (sd:p+ pt (+ wl2 300.0) (* 1000.0 dk)) (sd:p+ pt (+ wl2 300.0) (* 1000.0 fl))
                  (sd:p+ pt (+ wl2 300.0 bh) (* 1000.0 fl)) (sd:p+ pt (+ wl2 300.0 bh) (* 1000.0 dk))
                  (sd:p+ pt (+ wl2 300.0 bh ldd) (* 1000.0 (cond (dd) (dk))))) nil lay)
  (sd:line (sd:p+ pt (+ wl2 300.0) (* 1000.0 wl)) (sd:p+ pt (+ wl2 300.0 bh) (* 1000.0 wl)) lay)
  (sd:text (sd:p+ pt (+ wl2 300.0 (/ bh 2.0)) (+ (* 1000.0 wl) (* 2.0 sc))) (strcat "M\\U+1EF0C N\\U+01AF\\U+1EDAC " (sd:lc-rl wl)) (* 2.5 sc) "MC" lay)
  (sd:text (sd:p+ pt (+ wl2 300.0 (/ bh 2.0)) (- (* 1000.0 fl) (* 6.0 sc))) (strcat "\\U+0110\\U+00C1Y H\\U+1ED2 " (sd:lc-rl (- wl (/ ds 1000.0))) "  (s\\U+00E2u " (sd:num ds) ")") (* 2.5 sc) "MC" lay)
  (sd:text (sd:p+ pt wl2 (+ (* 1000.0 dk) (* 3.0 sc))) (strcat "S\\U+00C2N H\\U+1ED2 " (sd:lc-rl dk)) (* 2.5 sc) "L" lay)
  (if dd (sd:text (sd:p+ pt (+ wl2 300.0 bh ldd) (- (* 1000.0 dd) (* 6.0 sc))) (strcat "PH\\U+1EC4U / R\\U+00C3NH THU S\\U+00C2N " (sd:lc-rl dd)) (* 2.5 sc) "MR" lay))
  (princ "\n[SD] \\U+0110\\U+00E3 v\\U+1EBD m\\U+1EB7t c\\U+1EAFt ngang \\U+0111\\U+00FAng t\\U+1EC9 l\\U+1EC7 tr\\U+00EAn layer SD-CAODO-MC."))

;;; --------------------------------------------------------------------------
;;;  SDBACCAODO - Gan "du" cho cac cho doi cao do (nguong WC, mep ho, chan thanh): copy net sang layer SD-CAODO-BAC-<mm>, SDCATDU tu nhan
;;; --------------------------------------------------------------------------
(defun c:SDBACCAODO (/ ss i e dz kieu td kl mm lay ob ob2 n)
  (sd:begin)
  (princ "\nCh\\U+1ECDn c\\U+00E1c n\\U+00E9t (LINE / polyline) n\\U+1EB1m \\U+0111\\U+00FAng ch\\U+1ED7 \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9, vd m\\U+00E9p ng\\U+01B0\\U+1EE1ng WC, m\\U+00E9p h\\U+1ED3, ch\\U+00E2n th\\U+00E0nh: ")
  (if (setq ss (ssget '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC"))))
    (if (sd:dlg "Ch\\U+1EEBa d\\U+01B0 t\\U+1EA1i ch\\U+1ED7 \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9 (SDBACCAODO)"
                (list (list "kieu" "Ki\\U+1EC3u x\\U+1EED l\\U+00FD ch\\U+1ED7 \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9" 'kw (sd:cfg "BC-KIEU" "Dung")
                            '(("Dung" . "\\U+0110\\U+00E1 d\\U+01B0\\U+1EDBi chui d\\U+01B0\\U+1EDBi \\U+0111\\U+00E1 \\U+0111\\U+1EE9ng (\\U+0111\\U+00E1 \\U+0111\\U+1EE9ng d\\U+1EF1ng sau): d\\U+01B0 = d\\U+00E0y \\U+0111\\U+00E1 \\U+0111\\U+1EE9ng + keo") ("Op" . "\\U+0110\\U+00E1 s\\U+00E0n \\U+1ED1p l\\U+00EAn m\\U+1EB7t \\U+0111\\U+1EE9ng: d\\U+01B0 = ch\\U+00EAnh cao + keo")))
                      (list "dz" "Ch\\U+00EAnh cao t\\U+1EA1i ch\\U+1ED7 n\\U+00E0y (mm; m\\U+1EB7c \\U+0111\\U+1ECBnh = h\\U+1EA1 c\\U+1ED1t WC c\\U+1EE7a SDLIENCAODO)" 'real0 (sd:cfg "BC-DZ" (sd:cfg "LC-BC" 20.0)))
                      (list "td" "D\\U+00E0y \\U+0111\\U+00E1 \\U+0111\\U+1EE9ng (mm; d\\U+00F9ng cho ki\\U+1EC3u \\U+0111\\U+00E1 \\U+0111\\U+1EE9ng)" 'real0 (sd:cfg "BC-TD" 20.0))
                      (list "kl" "Keo ch\\U+1EEBa th\\U+00EAm (mm)" 'real0 (sd:cfg "BC-KL" 10.0))))
      (progn
        (setq kieu (sd:cfg-put "BC-KIEU" (cond ((sd:v "kieu")) ("Dung"))) dz (sd:cfg-put "BC-DZ" (cond ((sd:v "dz")) (0.0)))
              td (sd:cfg-put "BC-TD" (cond ((sd:v "td")) (0.0))) kl (sd:cfg-put "BC-KL" (cond ((sd:v "kl")) (0.0)))
              mm (+ kl (if (= kieu "Op") dz td)))
        (sd:ho-warn '("BC-TD" "BC-KL" "LC-BC"))
        (if (<= mm 0.0)
          (princ "\n[SD] S\\U+1ED1 mm d\\U+01B0 b\\U+1EB1ng 0: kh\\U+00F4ng l\\U+00E0m g\\U+00EC.")
          (progn
            (setq lay (sd:make-layer (strcat "SD-CAODO-BAC-" (sd:num mm)) 6 "Continuous" 25) i 0 n 0)
            (repeat (sslength ss)
              (setq e (ssname ss i) i (1+ i)
                    ob (vlax-ename->vla-object e)
                    ob2 (vl-catch-all-apply 'vla-copy (list ob)))
              (if (not (vl-catch-all-error-p ob2))
                (progn (vla-put-layer ob2 lay) (setq n (1+ n)))))
            (princ (strcat "\n[SD] \\U+0110\\U+00E3 copy " (itoa n) " n\\U+00E9t sang layer " lay " (d\\U+01B0 " (sd:num mm) " mm). SDCATDU s\\U+1EBD t\\U+1EF1 ch\\U+1EEBa d\\U+01B0 c\\U+00E1c c\\U+1EA1nh vi\\U+00EAn s\\U+00E1t nh\\U+1EEFng n\\U+00E9t n\\U+00E0y.")))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDMAP - Thu vien map (anh) da granite co san: chen anh tam da dung kich thuoc that de SDANHDA cat vao vien
;;;  Thu muc Maps canh SDOpLat.lsp (17 map); tha them .jpg / .png vao do la co trong danh sach.
;;; --------------------------------------------------------------------------
;; Ten map -> khoa chon (khong dau cach: initget tach theo dau cach)
(defun sd:map-key (base) (vl-string-translate " " "_" base))
;; Thu muc map: SDMAPDIR (nho trong may) -> Maps canh SDOpLat.lsp -> Maps canh ban ve; nil neu khong thay
(defun sd:map-dir (/ r d)
  (foreach p (append (list (getenv "SDMAPDIR"))
                     (mapcar '(lambda (x) (strcat (vl-string-right-trim "\\" x) "\\Maps"))
                             (append (list (cond ((findfile "SDOpLat.lsp") (vl-filename-directory (findfile "SDOpLat.lsp"))) ("")))
                                     (sd:split (cond ((getenv "ACAD")) ("")) ";")
                                     (list (cond ((getvar "DWGPREFIX")) (""))))))
    (if (and (null r) p (/= p "") (setq d (vl-string-right-trim "\\" p)) (vl-file-directory-p d)
             (or (vl-directory-files d "*.jpg" 1) (vl-directory-files d "*.png" 1)))
      (setq r d)))
  r)
;; Danh sach map trong thu muc: (khoa ten-hien-thi duong-dan-day-du), sap theo ten
(defun sd:map-list (dir / fs r b sz nm)
  (setq fs (append (vl-directory-files dir "*.jpg" 1) (vl-directory-files dir "*.jpeg" 1) (vl-directory-files dir "*.png" 1)))
  (foreach f (vl-sort fs '(lambda (a b) (< (strcase a) (strcase b))))
    (setq b (vl-filename-base f) sz (sd:map-size b)
          nm (vl-string-translate "-_" "  " (if sz (substr b 1 (vl-string-position (ascii "_") b 0 t)) b)))
    (setq r (cons (list (sd:map-key b) (if sz (strcat nm " (" (itoa (car sz)) " x " (itoa (cadr sz)) ")") nm) (strcat dir "\\" f) sz) r)))
  (reverse r))
;; Kho that ghi o cuoi ten file: Ten_3180x1920 -> (3180 1920); khong co -> nil
(defun sd:map-size (b / i p)
  (if (and (setq i (vl-string-position (ascii "_") b 0 t))
           (= (length (setq p (sd:split (strcase (substr b (+ i 2)) t) "x"))) 2)
           (> (atoi (car p)) 0) (> (atoi (cadr p)) 0))
    (list (atoi (car p)) (atoi (cadr p)))))
;; Chen mot anh file vao vi tri p, rong sw mm; tra ve doi tuong VLA hoac nil
(defun sd:map-put (file p sw / o)
  (if (not (vl-catch-all-error-p
             (setq o (vl-catch-all-apply 'vla-AddRaster (list (sd:ms) file (vlax-3d-point (car p) (cadr p) 0.0) 1.0 0.0)))))
    (progn
      (vla-ScaleEntity o (vlax-3d-point (car p) (cadr p) 0.0) (/ sw (vla-get-Width o)))
      (vla-put-Layer o "SD-MAP")
      o)))

(defun c:SDMAP (/ dir ls ch pick sw n gap p x o k nok fn w r)
  (sd:begin)
  (setq dir (sd:map-dir))
  (if (null dir)
    (progn
      (princ "\n[SD] Ch\\U+01B0a th\\U+1EA5y th\\U+01B0 m\\U+1EE5c Maps. Ch\\U+1ECDn m\\U+1ED9t \\U+1EA3nh b\\U+1EA5t k\\U+1EF3 trong th\\U+01B0 m\\U+1EE5c map (VD th\\U+01B0 m\\U+1EE5c SDOpLat\\Maps).")
      (if (setq fn (getfiled "Ch\\U+1ECDn m\\U+1ED9t \\U+1EA3nh trong th\\U+01B0 m\\U+1EE5c map" "" "jpg;png" 4))
        (progn (setq dir (vl-filename-directory fn)) (setenv "SDMAPDIR" dir)))))
  (setq ls (if dir (sd:map-list dir)))
  (cond
    ((null ls) (princ "\n[SD] Th\\U+01B0 m\\U+1EE5c map tr\\U+1ED1ng: ch\\U+00E9p c\\U+00E1c file .jpg / .png v\\U+00E0o \\U+0111\\U+00F3 (\\U+0111\\U+1EB7t t\\U+00EAn kh\\U+00F4ng d\\U+1EA5u) r\\U+1ED3i ch\\U+1EA1y l\\U+1EA1i SDMAP."))
    (t
     (setq ch (cons (cons "Tatca" "T\\U+1EA5t c\\U+1EA3 map, m\\U+1ED7i map m\\U+1ED9t t\\U+1EA5m (nhi\\U+1EC1u v\\U+00E2n kh\\U+00E1c nhau cho SDANHDA)")
                    (mapcar '(lambda (r) (cons (car r) (cadr r))) ls)))
     (if (sd:dlg (strcat "Ch\\U+00E8n map \\U+0111\\U+00E1 c\\U+00F3 s\\U+1EB5n (SDMAP) - " (itoa (length ls)) " map")
                 (list (list "map" "Ch\\U+1ECDn map" 'kw (cond ((vl-position (sd:cfg "MAP-LAST" "") (mapcar 'car ch)) (sd:cfg "MAP-LAST" "")) ("Tatca")) ch)
                       (list "sw" "Chi\\U+1EC1u d\\U+00E0i th\\U+1EADt c\\U+1EE7a t\\U+1EA5m \\U+0111\\U+00E1 (mm); 0 = theo kh\\U+1ED5 ghi trong t\\U+00EAn file (VD _3180x1920), kh\\U+00F4ng c\\U+00F3 th\\U+00EC 3000; chi\\U+1EC1u r\\U+1ED9ng theo t\\U+1EC9 l\\U+1EC7 \\U+1EA3nh" 'real0 (sd:cfg "MAP-SW" 0.0))
                       (list "so" "S\\U+1ED1 t\\U+1EA5m ch\\U+00E8n (ch\\U+1ECDn 1 map; m\\U+1ED7i t\\U+1EA5m c\\U+00F9ng v\\U+00E2n)" 'int (sd:cfg "MAP-SO" 1) nil '("map" "Tatca"))
                       (list "gap" "Kho\\U+1EA3ng c\\U+00E1ch gi\\U+1EEFa c\\U+00E1c t\\U+1EA5m (mm)" 'real0 (sd:cfg "MAP-GAP" 200.0))))
       (progn
         (setq pick (sd:cfg-put "MAP-LAST" (sd:v "map")) sw (sd:cfg-put "MAP-SW" (sd:v "sw"))
               n (sd:cfg-put "MAP-SO" (cond ((sd:v "so")) (1))) gap (sd:cfg-put "MAP-GAP" (cond ((sd:v "gap")) (0.0))))
         (if (setq p (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n g\\U+00F3c tr\\U+00E1i d\\U+01B0\\U+1EDBi c\\U+1EE7a t\\U+1EA5m \\U+0111\\U+1EA7u: " nil))
           (progn
             (sd:make-layer "SD-MAP" 8 "Continuous" 13)
             (setq x (car p) nok 0 k nil)
             (if (= pick "Tatca")
               (setq k ls)
               (repeat n (setq k (cons (assoc pick ls) k))))
             (foreach r k
               (setq w (cond ((> sw 0.0) sw) ((car (cadddr r))) (3000.0)))
               (if (setq o (sd:map-put (caddr r) (list x (cadr p)) w))
                 (progn (setq nok (1+ nok) x (+ x w gap)))
                 (princ (strcat "\n[SD] Kh\\U+00F4ng ch\\U+00E8n \\U+0111\\U+01B0\\U+1EE3c \\U+1EA3nh " (caddr r) " (\\U+0111\\U+1ECBnh d\\U+1EA1ng \\U+1EA3nh kh\\U+00F4ng h\\U+1EE3p l\\U+1EC7?)."))))
             (princ (strcat "\n[SD] \\U+0110\\U+00E3 ch\\U+00E8n " (itoa nok) " t\\U+1EA5m map (layer SD-MAP)."
                            "\n[SD] Ti\\U+1EBFp: SDANHDA > ch\\U+1ECDn c\\U+00E1c \\U+1EA3nh v\\U+1EEBa ch\\U+00E8n (b\\U+1EADt 'L\\U+1EA5y k\\U+00EDch th\\U+01B0\\U+1EDBc t\\U+1EA5m t\\U+1EEB \\U+1EA3nh') > qu\\U+00E9t c\\U+00E1c vi\\U+00EAn."
                            "\n[SD] Th\\U+00EAm map c\\U+1EE7a b\\U+1EA1n: ch\\U+00E9p file .jpg / .png v\\U+00E0o " dir "."))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDICHVAN - Dich van da tung buoc: nhich anh tam da duoi bien vien (trai / phai / len / xuong, buoc mm), bien vien dung yen, cat lai anh sau moi buoc
;;; --------------------------------------------------------------------------
;; Cat lai anh im theo da giac pts (xoa clip cu, tao clip da giac moi)

(defun sd:dv-clip (im pts / os)
  ;; tat OSNAP khi nhap toa do bang (command): net bat diem dang chay co the keo dinh polygon cat sang vien ke
  (setq os (getvar "OSMODE")) (setvar "OSMODE" 0)
  (command "_.IMAGECLIP" im "_D")
  (command "_.IMAGECLIP" im "_N" "_P")
  (foreach q pts (command (trans (list (car q) (cadr q) 0.0) 0 1)))
  (command "")
  (setq *SD:IMCLIPS* nil)
  (setvar "OSMODE" os))

;; Dich anh im them d = (dx dy) neu da giac pts van nam tron trong anh (chua le m); tra ve T neu da dich va cat lai
(defun sd:dv-try (im pts d m / g g2 f)
  (setq g (sd:im-geom im)
        g2 (list (list (+ (car (car g)) (car d)) (+ (cadr (car g)) (cadr d))) (cadr g) (caddr g) (cadddr g))
        f (sd:im-fit g2 pts m))
  (if (and f (< (distance '(0.0 0.0) f) 1e-6))
    (progn
      (vla-Move (vlax-ename->vla-object im) (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point (car d) (cadr d) 0.0))
      (sd:dv-clip im pts)
      t)))


(defun sd:dv-clip-new (im pts / os)
  (setq os (getvar "OSMODE")) (setvar "OSMODE" 0)
  (command "_.IMAGECLIP" im "_N" "_P")
  (foreach q pts (command (trans (list (car q) (cadr q) 0.0) 0 1)))
  (command "")
  (setq *SD:IMCLIPS* nil)
  (setvar "OSMODE" os))

;; Tong dich chuyen d = (dx dy) so voi anh goc g0 sau khi ep cho da giac pts nam tron trong anh (chua le m); nil neu da giac lon hon anh
(defun sd:dv-clamp (g0 pts d m / g2 f)
  (setq g2 (list (list (+ (car (car g0)) (car d)) (+ (cadr (car g0)) (cadr d))) (cadr g0) (caddr g0) (cadddr g0))
        f (sd:im-fit g2 pts m))
  (if f (list (+ (car d) (car f)) (+ (cadr d) (cadr f)))))

;; Ve vien da giac pts bang net sang tam thoi (grdraw) de thay vien dung yen khi keo anh
(defun sd:dv-outline (pts / a)
  (setq a (last pts))
  (foreach b pts (grdraw (list (car a) (cadr a)) (list (car b) (cadr b)) 1 1) (setq a b)))

;; Vong keo: anh bo clip, hien ca tam da mo di, vien dung yen; chuot / phim mui ten dich anh (ep cho vien luon nam trong anh)
;; Click trai / Enter / Space = chap nhan, Esc / chuot phai = huy. *SD:DVAP* luon ghi tong dich dang ap dung (de khoi phuc khi loi)
(defun sd:dv-drag-run (ob pts m step g0 base / done gr kind pt key d tgt lastpt)
  (setq lastpt base)
  (while (not done)
    (setq gr (grread T 15 0) kind (car gr) d nil)
    (cond
      ((= kind 5) (setq pt (trans (cadr gr) 1 0) lastpt pt d (list (- (car pt) (car base)) (- (cadr pt) (cadr base)))))
      ((= kind 3) (setq done 'ok))
      ((member kind '(25 11)) (setq done 'cancel))
      ((= kind 2)
       (setq key (cadr gr))
       (cond ((member key '(13 32)) (setq done 'ok))
             ((= key 27) (setq done 'cancel))
             ((= key 331) (setq d (list (- (car *SD:DVAP*) step) (cadr *SD:DVAP*))))
             ((= key 333) (setq d (list (+ (car *SD:DVAP*) step) (cadr *SD:DVAP*))))
             ((= key 328) (setq d (list (car *SD:DVAP*) (+ (cadr *SD:DVAP*) step))))
             ((= key 336) (setq d (list (car *SD:DVAP*) (- (cadr *SD:DVAP*) step))))
             (t nil))
       ;; sau phim mui ten, dich chuot tiep tuc tu vi tri hien tai
       (if d (setq base (list (- (car lastpt) (car d)) (- (cadr lastpt) (cadr d)))))))
    (if (and d (null done) (setq tgt (sd:dv-clamp g0 pts d m)))
      (progn
        (vla-Move ob (vlax-3d-point 0.0 0.0 0.0)
                  (vlax-3d-point (- (car tgt) (car *SD:DVAP*)) (- (cadr tgt) (cadr *SD:DVAP*)) 0.0))
        (setq *SD:DVAP* tgt)
        (sd:dv-outline pts))))
  done)

;; Keo van tu do: tra ve tong dich (dx dy) neu chap nhan va co dich, nil neu huy / khong dich
(defun sd:dv-drag (im pts m step / ob g0 base fade st r ap)
  (setq ob (vlax-ename->vla-object im) g0 (sd:im-geom im) *SD:DVAP* (list 0.0 0.0))
  (if (setq base (getpoint "\nCh\\U+1ECDn \\U+0111i\\U+1EC3m g\\U+1ED1c \\U+0111\\U+1EC3 k\\U+00E9o v\\U+00E2n (r\\U+1ED3i k\\U+00E9o chu\\U+1ED9t / ph\\U+00EDm m\\U+0169i t\\U+00EAn, Enter ho\\U+1EB7c click = ch\\U+1EA5p nh\\U+1EADn, Esc = h\\U+1EE7y): "))
    (progn
      (setq base (list (car base) (cadr base)) fade (vl-catch-all-apply 'vla-get-Fade (list ob)))
      (if (vl-catch-all-error-p fade) (setq fade nil))
      (command "_.IMAGECLIP" im "_D")
      (if fade (vl-catch-all-apply 'vla-put-Fade (list ob 50)))
      (setq r (vl-catch-all-apply 'sd:dv-drag-run (list ob pts m step g0 base)))
      (if (vl-catch-all-error-p r) (setq st 'cancel) (setq st r))
      (redraw)
      (if (= st 'cancel)
        (progn (vla-Move ob (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point (- (car *SD:DVAP*)) (- (cadr *SD:DVAP*)) 0.0))
               (setq *SD:DVAP* (list 0.0 0.0))))
      (if fade (vl-catch-all-apply 'vla-put-Fade (list ob fade)))
      (sd:dv-clip-new im pts)
      (setq ap *SD:DVAP*)
      (if (and (= st 'ok) (> (distance '(0.0 0.0) ap) 1e-6)) ap))
    (progn (command "_.IMAGECLIP" im "_D") (sd:dv-clip-new im pts) nil)))

;; Tam xoay vien = tam khung bao cua da giac pts
(defun sd:dv-ctr (pts / xs ys)
  (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts))
  (list (/ (+ (apply 'min xs) (apply 'max xs)) 2.0) (/ (+ (apply 'min ys) (apply 'max ys)) 2.0) 0.0))

;; Xoay anh im goc t (rad, +: nguoc chieu kim dong ho) quanh tam vien, roi dich nhe de vien van nam tron trong anh (chua le m); cat lai clip
;; Tra ve (fx fy t) de hoan; nil neu vien se vuot ra ngoai anh (khong xoay)

;; Cong goc xoay anh vao SD_ANH (goc anh so voi canh dai vien): neu khong, SDTUDONG / SDMOANH / SDRON se xoay anh tro lai huong cu
(defun sd:dv-adddelta (im d / xd)
  (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget im '("SD_ANH"))))))
  (if (and (>= (length xd) 3) (< (abs (nth 2 xd)) 50.0))
    (vl-catch-all-apply 'sd:put-xd
      (list im (list -3 (list "SD_ANH" (cons 1040 (car xd)) (cons 1040 (cadr xd))
                              (cons 1040 (rem (+ (nth 2 xd) d (* 4.0 pi)) (* 2.0 pi)))))))))

(defun sd:dv-rot (im pts t0 m / g c o2 g2 f ob lp)
  (setq g (sd:im-geom im) c (sd:dv-ctr pts) ob (vlax-ename->vla-object im)
        o2 (mapcar '+ c (sd:rot (list (- (car (car g)) (car c)) (- (cadr (car g)) (cadr c))) t0))
        g2 (list o2 (+ (cadr g) t0) (caddr g) (cadddr g))
        f (sd:im-fit g2 pts m))
  (if f
    (progn
      (vla-Rotate ob (vlax-3d-point (car c) (cadr c) 0.0) t0)
      (vla-Move ob (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point (car f) (cadr f) 0.0))
      (sd:dv-clip im pts)
      (sd:dv-adddelta im t0)
      (list (car f) (cadr f) t0))
    (progn
      (setq lp (mapcar '(lambda (q) (sd:w2l o2 (cadr g2) q)) pts))
      (princ (strcat "\n[SD] Khong xoay duoc " (sd:rtos (* 180.0 (/ t0 pi)) 1) " do: vien can khung "
                     (sd:rtos (- (apply 'max (mapcar 'car lp)) (apply 'min (mapcar 'car lp))) 0) " x "
                     (sd:rtos (- (apply 'max (mapcar 'cadr lp)) (apply 'min (mapcar 'cadr lp))) 0)
                     " mm trong anh, nhung tam anh chi " (sd:rtos (caddr g) 0) " x " (sd:rtos (cadddr g) 0) " mm."))
      nil)))

;; Hoan 1 buoc xoay (fx fy t)

(defun sd:dv-unrot (im pts h / ob c)
  (setq ob (vlax-ename->vla-object im) c (sd:dv-ctr pts))
  (vla-Move ob (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point (- (car h)) (- (cadr h)) 0.0))
  (vla-Rotate ob (vlax-3d-point (car c) (cadr c) 0.0) (- (caddr h)))
  (sd:dv-clip im pts)
  (sd:dv-adddelta im (- (caddr h)))
  t)

(defun c:SDDICHVAN (/ buoc goc m r e pts ims im kw hist d n)
  (sd:begin)
  (if (sd:dlg "D\\U+1ECBch v\\U+00E2n \\U+0111\\U+00E1 t\\U+1EEBng b\\U+01B0\\U+1EDBc (SDDICHVAN)"
              (list (list "buoc" "B\\U+01B0\\U+1EDBc d\\U+1ECBch m\\U+1ED7i l\\U+1EA7n (mm)" 'real (sd:cfg "DV-BUOC" 10.0))
                    (list "goc" "G\\U+00F3c xoay v\\U+00E2n m\\U+1ED7i l\\U+1EA7n (\\U+0111\\U+1ED9), d\\U+00F9ng cho QT / QP" 'real (sd:cfg "DV-GOC" 5.0))
                    (list "m" "Ch\\U+1EEBa l\\U+1EC1 an to\\U+00E0n m\\U+1ED7i c\\U+1EA1nh (mm)" 'real0 (sd:cfg "MOANH-M" 10.0))))
    (progn
      (setq buoc (sd:cfg-put "DV-BUOC" (sd:v "buoc")) goc (sd:cfg-put "DV-GOC" (sd:v "goc")) m (cond ((sd:v "m")) (0.0))
            ims (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH")))))
      (while (setq r (entsel "\nCh\\U+1ECDn vi\\U+00EAn c\\U+1EA7n d\\U+1ECBch v\\U+00E2n <Enter = xong>: "))
        (setq e (car r))
        (if (not (member (cdr (assoc 0 (entget e))) '("LWPOLYLINE" "IMAGE")))
          (princ "\n[SD] C\\U+1EA7n ch\\U+1ECDn polyline vi\\U+00EAn.")
          (progn
            (if (= (cdr (assoc 0 (entget e))) "IMAGE")
              (setq pts (sd:im-clip-pts e) im (if pts e))
              (setq pts (sd:curve-pts e) im (sd:im-find pts ims)))
            (setq hist nil n 0)
            (if (and (null im) (setq r (entsel "\nKh\\U+00F4ng t\\U+1EF1 gh\\U+00E9p \\U+0111\\U+01B0\\U+1EE3c \\U+1EA3nh. Ch\\U+1ECDn \\U+1EA3nh c\\U+1EE7a vi\\U+00EAn n\\U+00E0y <b\\U+1ECF qua>: ")))
              (if (= (cdr (assoc 0 (entget (car r)))) "IMAGE") (setq im (sd:im-adopt (car r) pts))))
            (if (null im)
              (princ "\n[SD] Kh\\U+00F4ng c\\U+00F3 \\U+1EA3nh \\U+0111\\U+1EC3 d\\U+1ECBch.")
              (progn
                (setq kw "")
                (while kw
                  (initget "Trai Phai Len Xuong Keo QT QP Xoay Hoan Buoc Goc Xong")
                  (setq kw (getkword (strcat "\nD\\U+1ECBch v\\U+00E2n " (sd:num buoc) " mm / " (sd:num goc) "\\U+00B0 [Trai/Phai/Len/Xuong/Keo/QT=quay tr\\U+00E1i/QP=quay ph\\U+1EA3i/Xoay=nhap goc/Hoan/Buoc/Goc/Xong] <Xong>: ")))
                  (cond
                    ((or (null kw) (= kw "Xong")) (setq kw nil))
                    ((= kw "Buoc")
                     (setq buoc (cond ((getdist (strcat "\nB\\U+01B0\\U+1EDBc d\\U+1ECBch (mm) <" (sd:num buoc) ">: "))) (buoc)))
                     (sd:cfg-put "DV-BUOC" buoc))
                    ((= kw "Goc")
                     (setq goc (cond ((getreal (strcat "\nG\\U+00F3c xoay m\\U+1ED7i l\\U+1EA7n (\\U+0111\\U+1ED9) <" (sd:num goc) ">: "))) (goc)))
                     (sd:cfg-put "DV-GOC" goc))
                    ((= kw "Xoay")
                     (if (setq d (getreal "\nGoc xoay van (do; duong = nguoc chieu kim dong ho, am = cung chieu): "))
                       (if (setq d (sd:dv-rot im pts (/ (* d pi) 180.0) m))
                         (setq hist (cons d hist)))))
                    ((member kw '("QT" "QP"))
                     (if (setq d (sd:dv-rot im pts (* (if (= kw "QT") 1.0 -1.0) (/ (* goc pi) 180.0)) m))
                       (setq hist (cons d hist))
                       (princ "\n[SD] Xoay th\\U+00EAm th\\U+00EC vi\\U+00EAn v\\U+01B0\\U+1EE3t ra ngo\\U+00E0i t\\U+1EA5m \\U+1EA3nh: kh\\U+00F4ng xoay. Th\\U+1EED g\\U+00F3c nh\\U+1ECF h\\U+01A1n ho\\U+1EB7c xoay chi\\U+1EC1u ng\\U+01B0\\U+1EE3c l\\U+1EA1i.")))
                    ((= kw "Keo")
                     (if (setq d (sd:dv-drag im pts m buoc))
                       (setq hist (cons d hist))
                       (princ "\n[SD] Kh\\U+00F4ng d\\U+1ECBch (\\U+0111\\U+00E3 h\\U+1EE7y ho\\U+1EB7c ch\\U+01B0a k\\U+00E9o).")))
                    ((= kw "Hoan")
                     (cond ((null hist) (princ "\n[SD] Kh\\U+00F4ng c\\U+00F2n b\\U+01B0\\U+1EDBc \\U+0111\\U+1EC3 ho\\U+00E0n."))
                           ((= (length (car hist)) 3) (sd:dv-unrot im pts (car hist)) (setq hist (cdr hist)))
                           ((sd:dv-try im pts (list (- (car (car hist))) (- (cadr (car hist)))) m) (setq hist (cdr hist)))
                           (t (princ "\n[SD] Kh\\U+00F4ng ho\\U+00E0n \\U+0111\\U+01B0\\U+1EE3c b\\U+01B0\\U+1EDBc n\\U+00E0y."))))
                    (t
                     (setq d (cond ((= kw "Trai") (list (- buoc) 0.0)) ((= kw "Phai") (list buoc 0.0)) ((= kw "Len") (list 0.0 buoc)) (t (list 0.0 (- buoc)))))
                     (if (sd:dv-try im pts d m)
                       (setq hist (cons d hist))
                       (princ "\n[SD] H\\U+1EBFt kh\\U+1ED5 v\\U+1EC1 ph\\U+00EDa \\U+0111\\U+00F3 (c\\U+00F2n l\\U+1EC1 an to\\U+00E0n): kh\\U+00F4ng d\\U+1ECBch th\\U+00EAm \\U+0111\\U+01B0\\U+1EE3c. Th\\U+1EED h\\U+01B0\\U+1EDBng kh\\U+00E1c ho\\U+1EB7c b\\U+01B0\\U+1EDBc nh\\U+1ECF h\\U+01A1n.")))))
                (princ (strcat "\n[SD] T\\U+1ED5ng \\U+0111\\U+00E3 d\\U+1ECBch v\\U+00E2n: X " (sd:rtos (apply '+ (cons 0.0 (mapcar 'car (vl-remove-if-not '(lambda (h) (= (length h) 2)) hist)))) 1) " mm, Y "
                               (sd:rtos (apply '+ (cons 0.0 (mapcar 'cadr (vl-remove-if-not '(lambda (h) (= (length h) 2)) hist)))) 1) " mm (Ph\\U+1EA3i / L\\U+00EAn l\\U+00E0 d\\U+01B0\\U+01A1ng), xoay "
                               (sd:rtos (/ (* 180.0 (apply '+ (cons 0.0 (mapcar 'caddr (vl-remove-if-not '(lambda (h) (= (length h) 3)) hist))))) pi) 1) "\\U+00B0 (tr\\U+00E1i l\\U+00E0 d\\U+01B0\\U+01A1ng).")))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDLOP - Chi tiet cau tao lop op / lat (san hoac tuong)
;;; --------------------------------------------------------------------------
(defun sd:parse-layers (s / r tok p)
  (foreach tok (sd:split s ";")
    (setq tok (vl-string-trim " " tok))
    (if (and (/= tok "") (setq p (vl-string-position (ascii " ") tok nil t))
             (> (atof (substr tok (+ p 2))) 0))
      (setq r (cons (list tok (atof (substr tok (+ p 2)))) r))))
  (reverse r))

(defun c:SDLOP (/ ts ori lays L o n x y mids bnd i tl yl xl r)
  (sd:begin)
  (setq ts (float *SD:DETSCALE*))
  (if (not (sd:dlg "Cau tao lop op / lat (SDLOP)"
                   (list (list "ori" "Cau tao" 'kw "San" '(("San" . "San") ("Tuong" . "Tuong")))
                         (list "note" "Cac lop tu mat hoan thien vao, cach nhau ; - so cuoi moi lop la chieu day (mm)" 'note nil)
                         (list "lop" "Cac lop" 'str (cond (*SD:LOP*) ("Da granite day 20;Vua xi mang M75 day 30;San BTCT 150")))
                         (list "L" "Chieu dai doan the hien (mm)" 'real 600.0))))
    (exit))
  (setq ori (sd:v "ori") *SD:LOP* (sd:v "lop") lays (sd:parse-layers *SD:LOP*) L (sd:v "L"))
  (if (and lays (setq o (sd:getpt (if (= ori "San") "\nDiem chen (goc trai mat hoan thien): "
                                      "\nDiem chen (chan mat hoan thien): ") nil)))
    (progn
      (setq n (length lays) i 0 tl (* ts (max 40.0 (apply 'max (mapcar '(lambda (x) (* 1.6 (strlen (car x)))) lays)))))
      (sd:use-dimstyle ts)
      (if (= ori "San")
        (progn
          ;; cac lop xep tu tren xuong
          (setq y 0.0 bnd (list (sd:p+ o 0 0)))
          (foreach ly lays
            (sd:rect (sd:p+ o 0 (- y (cadr ly))) L (cadr ly) "SD-OP-LOP")
            (setq mids (cons (- y (/ (cadr ly) 2.0)) mids)
                  y (- y (cadr ly))
                  bnd (cons (sd:p+ o 0 y) bnd)))
          (setq mids (reverse mids) xl (* 0.7 L))
          (sd:dimchain (reverse bnd) "V" (sd:p+ o (* -8 ts) 0))
          ;; duong dan dung + danh sach ghi chu (lop tren cung ghi tren cung)
          (sd:line (sd:p+ o xl (last mids)) (sd:p+ o xl (+ (* 6 ts) (* 5 ts (1- n)))) "SD-KYHIEU")
          (foreach ly lays
            (setq yl (+ (* 6 ts) (* 5 ts (- n 1 i))))
            (sd:dot (sd:p+ o xl (nth i mids)) ts "SD-KYHIEU")
            (sd:line (sd:p+ o xl yl) (sd:p+ o (+ xl tl) yl) "SD-KYHIEU")
            (sd:text (sd:p+ o (+ xl ts) (+ yl (* 0.8 ts))) (car ly) (* 2.5 ts) "L" "SD-CHU")
            (setq i (1+ i))))
        (progn
          ;; tuong: mat hoan thien ben trai, cac lop xep sang phai
          (setq x 0.0 bnd (list (sd:p+ o 0 0)))
          (foreach ly lays
            (sd:rect (sd:p+ o x 0) (cadr ly) L "SD-OP-LOP")
            (setq mids (cons (+ x (/ (cadr ly) 2.0)) mids)
                  x (+ x (cadr ly))
                  bnd (cons (sd:p+ o x 0) bnd)))
          (setq mids (reverse mids) yl (* 0.7 L) xl (* -10 ts))
          (sd:dimchain (reverse bnd) "H" (sd:p+ o 0 (* -8 ts)))
          (sd:line (sd:p+ o (last mids) yl) (sd:p+ o xl yl) "SD-KYHIEU")
          (sd:line (sd:p+ o xl yl) (sd:p+ o xl (+ yl (* 5 ts n))) "SD-KYHIEU")
          (foreach ly lays
            (setq r (+ yl (* 5 ts (- n i))))
            (sd:dot (sd:p+ o (nth i mids) yl) ts "SD-KYHIEU")
            (sd:line (sd:p+ o xl r) (sd:p+ o (- xl tl) r) "SD-KYHIEU")
            (sd:text (sd:p+ o (- xl ts) (+ r (* 0.8 ts))) (car ly) (* 2.5 ts) "R" "SD-CHU")
            (setq i (1+ i)))))
      (sd:use-dimstyle *SD:SCALE*)))
  (if (null lays) (princ "\n[SD] Khong doc duoc lop nao. Vi du: Da granite 20;Vua XM 30;San BTCT 150"))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDCHANTUONG - Len chan tuong: chia vien doc theo tuong, tru lo cua
;;; --------------------------------------------------------------------------
(defun sd:subtract (a b doors / res cur)
  (setq cur a)
  (foreach d doors
    (if (and (< (car d) b) (> (cadr d) cur))
      (progn
        (if (> (car d) cur) (setq res (cons (list cur (car d)) res)))
        (setq cur (max cur (cadr d))))))
  (if (< cur b) (setq res (cons (list cur b) res)))
  (reverse res))

(defun c:SDCHANTUONG (/ sc es e mat name lc hc tk jt doors p1 p2 d1 d2 pts segs closed side
                        dacc p q len fa nv a b pcs poly n tot rc elev bnds vinfo ep i r yt)
  (sd:begin)
  (setq sc (sd:sc))
  (setq es (entsel "\nChon duong mat tuong (polyline, kin hoac ho): "))
  (if (not (and es (= (cdr (assoc 0 (entget (car es)))) "LWPOLYLINE")))
    (princ "\n[SD] Can chon 1 polyline the hien mat tuong.")
    (progn
      (setq e (car es) closed (vlax-curve-isClosed e) pts (sd:curve-pts e))
      (if (not (sd:dlg "Len chan tuong (SDCHANTUONG)"
                       (list (list "mat" "Ma len chan tuong" 'str (cond (*SD:LCODE*) ("L1")))
                             (list "name" "Ten vat lieu" 'str (cond (*SD:LNAME*) ("Len granite")))
                             (list "lc" "Chieu dai 1 vien len (mm)" 'real (cond (*SD:LLC*) (600.0)))
                             (list "hc" "Chieu cao len (mm)" 'real (cond (*SD:LHC*) (120.0)))
                             (list "tk" "Chieu day len (mm)" 'real (cond (*SD:LTK*) (18.0)))
                             (list "jt" "Mach giua cac vien (mm)" 'real0 1.0)
                             (list "elev" "Ve trien khai mat dung" 'tog t))))
        (exit))
      (setq mat (sd:v "mat") name (sd:v "name") lc (sd:v "lc") hc (sd:v "hc") tk (sd:v "tk") jt (sd:v "jt"))
      (setq *SD:LCODE* mat *SD:LNAME* name *SD:LLC* lc *SD:LHC* hc *SD:LTK* tk)
      ;; phia trong phong
      (if closed
        (setq side (if (> (sd:area pts) 0) 1.0 -1.0))
        (if (setq p (sd:getpt "\nChon 1 diem phia trong phong: " nil))
          (setq side (if (> (- (* (- (car (cadr pts)) (car (car pts))) (- (cadr p) (cadr (car pts))))
                               (* (- (cadr (cadr pts)) (cadr (car pts))) (- (car p) (car (car pts)))))
                            0) 1.0 -1.0))
          (setq side 1.0)))
      ;; lo cua
      (while (and (setq p1 (sd:getpt "\nDiem dau lo cua tren duong tuong <Enter = het>: " nil))
                  (setq p2 (sd:getpt "\nDiem cuoi lo cua: " p1)))
        (setq d1 (vlax-curve-getDistAtPoint e (vlax-curve-getClosestPointTo e p1))
              d2 (vlax-curve-getDistAtPoint e (vlax-curve-getClosestPointTo e p2))
              doors (cons (list (min d1 d2) (max d1 d2)) doors)))
      (setq doors (sd:sort doors '(lambda (x y) (< (car x) (car y))))
            segs  (mapcar 'list pts (if closed (append (cdr pts) (list (car pts))) (cdr pts))))
      (setq dacc 0.0 tot 0.0)
      (foreach s segs
        (setq p (car s) q (cadr s) len (distance p q) fa (angle p q)
              nv (+ fa (* side (/ pi 2)))
              bnds (cons dacc bnds)
              vinfo (cons (list p fa nv) vinfo))
        (foreach iv (sd:subtract dacc (+ dacc len) doors)
          (setq a (- (car iv) dacc))
          (while (< a (- (cadr iv) dacc 1.0))
            (setq b (min (+ a lc) (- (cadr iv) dacc))
                  poly (list (polar p fa a) (polar p fa b) (polar (polar p fa b) nv tk) (polar (polar p fa a) nv tk))
                  poly (mapcar 'sd:2d poly))
            (sd:pline poly t "SD-LEN-CHAN")
            (setq pcs (cons (list (list (entlast)) (- b a) hc (* (- b a) hc)
                                  (if (equal (- b a) lc 0.5) "F" "C")
                                  (sd:centroid poly) (list a 0.0) (sd:2d p) fa)
                            pcs)
                  tot (+ tot (- b a))
                  elev (cons (list (+ dacc a) (+ dacc b) (entlast)) elev)
                  a (+ b jt))))
        (setq dacc (+ dacc len)))
      (setq rc (sd:code-pieces pcs mat name lc hc tk nil sc))
      ;; ---- trien khai mat dung (tuong duoc trai phang theo thu tu canh)
      (setq bnds (reverse (cons dacc bnds)) vinfo (reverse vinfo) r (* 2.5 sc) yt (+ hc (* 12 sc)))
      (if (and (sd:v "elev")
               (setq ep (sd:getpt "\nDiem chen mat dung (dau tuong, cao do san): " nil)))
        (progn
          (sd:line ep (sd:p+ ep dacc 0) "SD-BANG")
          (foreach v elev
            (sd:rect (sd:p+ ep (car v) 0) (- (cadr v) (car v)) hc "SD-LEN-CHAN")
            (sd:text (sd:p+ ep (/ (+ (car v) (cadr v)) 2) (/ hc 2))
                     (nth 2 (mapcar 'cdr (cdadr (assoc -3 (entget (caddr v) '("SD_TILE"))))))
                     (min (* 2.0 sc) (* 0.35 hc) (* 0.3 (- (cadr v) (car v)))) "MC" "SD-CHU"))
          ;; lo cua
          (foreach d doors
            (sd:line (sd:p+ ep (car d) 0) (sd:p+ ep (car d) (* 3 hc)) "SD-KHUAT")
            (sd:line (sd:p+ ep (cadr d) 0) (sd:p+ ep (cadr d) (* 3 hc)) "SD-KHUAT")
            (sd:text (sd:p+ ep (/ (+ (car d) (cadr d)) 2) (* 1.5 hc)) "C\\U+1EECA" (* 2.5 sc) "MC" "SD-CHU"))
          ;; goc tuong: duong truc tren mat dung + so goc, danh so tuong ung tren mat bang
          (setq i 0)
          (foreach x bnds
            (sd:line (sd:p+ ep x 0) (sd:p+ ep x (- yt r)) "SD-TRUC")
            (sd:bubble (sd:p+ ep x yt) r (itoa (1+ (rem i (length pts)))))
            (if (nth i vinfo)
              (sd:bubble (polar (polar (car (nth i vinfo)) (caddr (nth i vinfo)) (* 6 sc))
                                (cadr (nth i vinfo)) (* 6 sc))
                         r (itoa (1+ i))))
            (setq i (1+ i)))
          (if (and (not closed) (last pts) (> (length bnds) (length vinfo)))
            (sd:bubble (polar (last pts) (caddr (last vinfo)) (* 6 sc)) r (itoa (length bnds))))
          (sd:use-dimstyle sc)
          (sd:dimchain (mapcar '(lambda (x) (sd:p+ ep x 0)) bnds) "H" (sd:p+ ep 0 (* -8 sc)))
          (sd:dim ep (sd:p+ ep 0 hc) "V" (sd:p+ ep (* -8 sc) 0))
          (sd:text (sd:p+ ep 0 (* -20 sc))
                   (strcat "TRI\\U+1EC2N KHAI M\\U+1EB6T \\U+0110\\U+1EE8NG LEN CH\\U+00C2N T\\U+01AF\\U+1EDCNG " mat " - cao " (sd:num hc)
                           ", d\\U+00E0y " (sd:num tk) ", d\\U+00E0i " (sd:rtos (/ tot 1000.0) 2) " m")
                   (* 3.0 sc) "L" "SD-CHU")))
      (princ (strcat "\n[SD] " mat ": tong chieu dai " (sd:rtos (/ tot 1000.0) 2) " m; "
                     (itoa (length (vl-remove-if-not '(lambda (x) (= (nth 4 x) "F")) pcs))) " vien nguyen, "
                     (itoa (length (vl-remove-if '(lambda (x) (= (nth 4 x) "F")) pcs))) " vien cat ("
                     (itoa (car rc)) " ma); dien tich " (sd:rtos (/ (* tot hc) 1e6) 2) " m2."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  Doc vien op lat (XDATA SD_TILE) -> ((maVL . ((maVien SL ename xd) ...)) ...)
;;; --------------------------------------------------------------------------
(defun sd:tile-groups (ss / i e xd key g grp)
  (setq i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i)
          xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
    (if (/= (nth 1 xd) "X")
      (progn
        (setq key (strcat (nth 0 xd) "|" (nth 2 xd)))
        (if (setq g (assoc key grp))
          (setq grp (subst (list key (1+ (nth 1 g)) (nth 2 g) (nth 3 g)) g grp))
          (setq grp (cons (list key 1 e xd) grp))))))
  (sd:sort grp
    '(lambda (a b)
       (cond ((/= (car (nth 3 a)) (car (nth 3 b))) (< (car (nth 3 a)) (car (nth 3 b))))
             ((/= (= (nth 1 (nth 3 a)) "F") (= (nth 1 (nth 3 b)) "F")) (= (nth 1 (nth 3 a)) "F"))
             (t (< (sd:pc-idx (nth 2 (nth 3 a))) (sd:pc-idx (nth 2 (nth 3 b)))))))))

(defun sd:select-tiles (msg / flt)
  (setq flt '((-3 ("SD_TILE"))))
  (princ msg)
  (cond ((ssget flt)) ((ssget "_X" flt))))

;;; --------------------------------------------------------------------------
;;;  SDGIACONG - Ban ve gia cong tung ma vien cat (gui xuong)
;;; --------------------------------------------------------------------------
(defun sd:dimal (p1 p2 pd / os cl)
  (setq os (getvar "OSMODE") cl (getvar "CLAYER"))
  (setvar "OSMODE" 0)
  (setvar "CLAYER" "SD-KICHTHUOC")
  (command "_.DIMALIGNED" (trans p1 0 1) (trans p2 0 1) (trans pd 0 1))
  (setvar "CLAYER" cl)
  (setvar "OSMODE" os))

;; Vong lo khoet (loai X) cung ma vien, nam trong bao cua vien dai dien
(defun sd:piece-holes (e pc / bb ss i x xd r)
  (setq bb (sd:bbox (sd:curve-pts e)))
  (if (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (-3 ("SD_TILE")))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq x (ssname ss i) i (1+ i)
              xd (mapcar 'cdr (cdadr (assoc -3 (entget x '("SD_TILE"))))))
        (if (and (= (nth 1 xd) "X") (= (nth 2 xd) pc)
                 (vl-every '(lambda (p) (and (<= (car (car bb)) (car p) (car (cadr bb)))
                                             (<= (cadr (car bb)) (cadr p) (cadr (cadr bb)))))
                           (sd:curve-pts x)))
          (setq r (cons (sd:curve-pts x) r))))))
  r)

(defun c:SDGIACONG (/ ss inclF ts grp pt cx cy col rowh xd n e typ w h fa thk loops mn po cw ch
                      rg mnp mxp sg p1 p2 ncol dx dy l)
  (sd:begin)
  (if (not (setq ss (sd:select-tiles "\nChon cac vien can ve gia cong <Enter = tat ca>: ")))
    (princ "\n[SD] Khong tim thay vien nao (SDGACH / SDCHANTUONG).")
    (progn
      (if (not (sd:dlg "Ban ve gia cong vien (SDGIACONG)"
                       (list (list "inclF" "Ve ca vien nguyen" 'tog nil)
                             (list "ts" "Ty le ban ve gia cong 1/" 'int (cond (*SD:GCSC*) (10)))
                             (list "ncol" "So the vien tren 1 hang" 'int 4))))
        (exit))
      (setq inclF (sd:v "inclF")
            ts    (float (sd:v "ts"))
            ncol  (sd:v "ncol")
            *SD:GCSC* (fix ts)
            grp   (sd:tile-groups ss))
      (if (setq pt (sd:getpt "\nDiem chen (goc trai tren): " nil))
        (progn
          (sd:use-dimstyle ts)
          (setq cx (car pt) cy (cadr pt) col 0 rowh 0.0)
          (foreach g grp
            (setq xd (nth 3 g) n (nth 1 g) e (nth 2 g) typ (nth 1 xd)
                  w (nth 3 xd) h (nth 4 xd)
                  fa (cond ((nth 10 xd)) (0.0)) thk (cond ((nth 11 xd)) (0.0))
                  loops nil rg nil)
            (if (or inclF (/= typ "F"))
              (progn
                ;; hinh dang vien trong he toa do cua vien, goc trai duoi = (0,0)
                (cond
                  ((and (member typ '("F" "C")) (/= (nth 12 xd) "G"))
                   (setq loops (list (list '(0.0 0.0) (list w 0.0) (list w h) (list 0.0 h)))))
                  ((= (cdr (assoc 0 (entget e))) "LWPOLYLINE")
                   (setq loops (mapcar '(lambda (lp) (mapcar '(lambda (p) (sd:w2l '(0.0 0.0) fa p)) lp))
                                       (cons (sd:curve-pts e) (sd:piece-holes e (nth 2 xd))))
                         mn (car (sd:bbox (car loops)))
                         loops (mapcar '(lambda (lp) (mapcar '(lambda (p) (list (- (car p) (car mn)) (- (cadr p) (cadr mn)))) lp))
                                       loops)
                         w (car (cadr (sd:bbox (car loops)))) h (cadr (cadr (sd:bbox (car loops))))))
                  (t (setq rg (vla-Copy (vlax-ename->vla-object e)))))
                (setq cw (max (+ w (* 24 ts)) (* 75 ts))
                      ch (+ h (* 30 ts))
                      po (list (+ cx (* 14 ts)) (- cy (* 14 ts) h) 0.0))
                ;; vien cong (region): xoay ve phuong vien va dat vao the
                (if rg
                  (progn
                    (vla-Rotate rg (vlax-3d-point '(0.0 0.0 0.0)) (- fa))
                    (vla-GetBoundingBox rg 'mnp 'mxp)
                    (setq mnp (vlax-safearray->list mnp) mxp (vlax-safearray->list mxp))
                    (vla-Move rg (vlax-3d-point mnp) (vlax-3d-point po))
                    (vla-put-Layer rg "SD-GIACONG")
                    (setq w (- (car mxp) (car mnp)) h (- (cadr mxp) (cadr mnp)))))
                (foreach lp loops
                  (sd:pline (mapcar '(lambda (p) (sd:p+ po (car p) (cadr p))) lp) t "SD-GIACONG"))
                ;; kich thuoc bao
                (sd:dim po (sd:p+ po w 0) "H" (sd:p+ po 0 (* -8 ts)))
                (sd:dim po (sd:p+ po 0 h) "V" (sd:p+ po (* -8 ts) 0))
                ;; vien dac biet: ghi tung canh (tru canh bang kich thuoc bao) va canh lo
                (if (and (or (= typ "D") (= (nth 12 xd) "G")) loops)
                  (foreach lp loops
                    (setq sg (if (> (sd:area lp) 0) 1.0 -1.0))
                    (mapcar
                      '(lambda (a b / dx dy l)
                         (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l (distance a b))
                         (if (and (> l 1.0)
                                  (not (and (equal dy 0.0 0.01) (equal l w 0.5)))
                                  (not (and (equal dx 0.0 0.01) (equal l h 0.5))))
                           (sd:dimal (sd:p+ po (car a) (cadr a)) (sd:p+ po (car b) (cadr b))
                                     (sd:p+ po (+ (/ (+ (car a) (car b)) 2) (* sg (/ dy l) 4 ts))
                                               (- (/ (+ (cadr a) (cadr b)) 2) (* sg (/ dx l) 4 ts))))))
                      lp (append (cdr lp) (list (car lp))))))
                ;; tieu de the
                (sd:text (list (+ cx (* 2 ts)) (- cy (* 5 ts))) (nth 2 xd) (* 3.5 ts) "L" "SD-CHU")
                (sd:text (list (+ cx (* 2 ts)) (- cy (* 9.5 ts)))
                         (strcat "SL: " (itoa n) " vi\\U+00EAn | " (sd:rtos w 0) "\\U+00D7" (sd:rtos h 0)
                                 (if (> thk 0) (strcat "\\U+00D7" (sd:num thk)) "") " | " (nth 7 xd))
                         (* 2.2 ts) "L" "SD-CHU")
                (sd:rect (list cx (- cy ch) 0.0) cw ch "SD-BANG")
                (setq rowh (max rowh ch) col (1+ col) cx (+ cx cw))
                (if (>= col ncol) (setq col 0 cx (car pt) cy (- cy rowh) rowh 0.0)))))
          (sd:use-dimstyle *SD:SCALE*)
          (princ (strcat "\n[SD] Da ve the gia cong cho "
                         (itoa (length (if inclF grp (vl-remove-if '(lambda (g) (= (nth 1 (nth 3 g)) "F")) grp))))
                         " ma vien."))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDATHO - Cat vien tu tam da tho (slab): toi uu 2D, so do cat, hieu suat
;;; --------------------------------------------------------------------------
;; Tim cho dat tot nhat trong cac o trong. fm: 0 it thua canh ngan nhat (BSSF), 1 it thua canh dai nhat, 2 it thua dien tich;
;; vua khit mot canh thi uu tien (cat duoc ca dai, it vun)
(defun sd:gfit (frs w h rot fm / best i sc lw lh)
  (setq i 0)
  (foreach fr frs
    (foreach o (if rot (list (list w h 0) (list h w 1)) (list (list w h 0)))
      (if (and (<= (car o) (+ (nth 2 fr) 1e-6)) (<= (cadr o) (+ (nth 3 fr) 1e-6)))
        (progn
          (setq lw (- (nth 2 fr) (car o)) lh (- (nth 3 fr) (cadr o))
                sc (cond ((= fm 1) (max lw lh))
                         ((= fm 2) (- (* (nth 2 fr) (nth 3 fr)) (* (car o) (cadr o))))
                         (t (min lw lh))))
          (if (or (< lw 1.0) (< lh 1.0)) (setq sc (- sc 1e8)))
          (if (or (null best) (< sc (car best))) (setq best (list sc i (car o) (cadr o) (caddr o)))))))
    (setq i (1+ i)))
  best)

;; Dat vien vao o, chia o con lai kieu guillotine (cat thang suot tam)
;; tam = (o-trong dat-vien ma-loai-tam); dat-vien = (ma x y rong cao xoay)
;; sm: 0 tach theo canh thua ngan (nhu cu), 1 theo canh thua dai, 2 giu o lon nhat, 3 luon ngang truoc, 4 luon dung truoc
(defun sd:gplace (slab f code k sm / frs fr fx fy fw fh ww hh rw rh hfirst)
  (setq frs (car slab) fr (nth (nth 1 f) frs) ww (nth 2 f) hh (nth 3 f)
        fx (nth 0 fr) fy (nth 1 fr) fw (nth 2 fr) fh (nth 3 fr)
        rw (- fw ww) rh (- fh hh)
        frs (sd:remove-nth (nth 1 f) frs)
        hfirst (cond ((= sm 1) (> rw rh))
                     ((= sm 2) (>= (max (* fw rh) (* rw hh)) (max (* rw fh) (* ww rh))))
                     ((= sm 3) t)
                     ((= sm 4) nil)
                     (t (< rw rh))))
  (foreach nr (if hfirst
                (list (list (+ fx ww) fy rw hh) (list fx (+ fy hh) fw rh))
                (list (list (+ fx ww) fy rw fh) (list fx (+ fy hh) ww rh)))
    (if (and (> (nth 2 nr) 1e-6) (> (nth 3 nr) 1e-6)) (setq frs (cons nr frs))))
  (append (list frs (cons (list code fx fy (- ww k) (- hh k) (nth 4 f)) (cadr slab))) (cddr slab)))

;; Loai tam: (ma rong-dung dai-dung so-luong dai-that rong-that [R = tam du]); so-luong -1 = khong gioi han
(defun sd:fits (tp w h rot)
  (or (and (<= w (nth 1 tp)) (<= h (nth 2 tp)))
      (and rot (<= h (nth 1 tp)) (<= w (nth 2 tp)))))

;; Chon loai tam mo moi: tam du (R) vua nho nhat truoc (uu = T), roi tam kho nguyen (tm 0 lon nhat / tm 1 nho nhat vua), het moi dung tam "MOI" (mua)
(defun sd:pick-type (types w h rot tm uu / best rbest)
  (foreach tp types
    (if (and (/= (car tp) "MOI") (/= (nth 3 tp) 0) (sd:fits tp w h rot))
      (if (and uu (nth 6 tp))
        (if (or (null rbest) (< (* (nth 1 tp) (nth 2 tp)) (* (nth 1 rbest) (nth 2 rbest)))) (setq rbest tp))
        (if (or (null best)
                (if (= tm 1)
                  (< (* (nth 1 tp) (nth 2 tp)) (* (nth 1 best) (nth 2 best)))
                  (> (* (nth 1 tp) (nth 2 tp)) (* (nth 1 best) (nth 2 best)))))
          (setq best tp)))))
  (cond (rbest)
        (best)
        ((and (setq best (assoc "MOI" types)) (sd:fits best w h rot)) best)))

(defun sd:add-type (types id n)
  (mapcar '(lambda (tp)
             (if (and (= (car tp) id) (>= (nth 3 tp) 0))
               (list (nth 0 tp) (nth 1 tp) (nth 2 tp) (+ (nth 3 tp) n) (nth 4 tp) (nth 5 tp) (nth 6 tp))
               tp))
          types))

;; Xep vien len cac tam. Tra ve (danh-sach-tam loai-tam-con-lai vien-khong-xep-duoc)
;; fm / sm: cach cham diem o trong / cach tach o; tm: chon tam kho (0 lon nhat, 1 nho nhat vua); uu: uu tien tam du
(defun sd:slab-pack (pcs types rot k fm sm tm uu / slabs f i done s tp nofit)
  (foreach p pcs
    (setq done nil i 0)
    (while (and (not done) (< i (length slabs)))
      (if (setq f (sd:gfit (car (nth i slabs)) (cadr p) (caddr p) rot fm))
        (setq slabs (sd:replace-nth i (sd:gplace (nth i slabs) f (car p) k sm) slabs) done t))
      (setq i (1+ i)))
    (if (not done)
      (if (setq tp (sd:pick-type types (cadr p) (caddr p) rot tm uu))
        (setq types (sd:add-type types (car tp) -1)
              s     (list (list (list 0.0 0.0 (nth 1 tp) (nth 2 tp))) nil (car tp))
              f     (sd:gfit (car s) (cadr p) (caddr p) rot fm)
              slabs (append slabs (list (sd:gplace s f (car p) k sm))))
        (setq nofit (cons (car p) nofit)))))
  (list slabs types nofit))

;; Doi tam dung it sang loai tam nho hon con trong kho (hoac tam du) neu chua du het vien cua tam do
(defun sd:downsize (slabs types rot k / out cur pcs cands res done)
  (foreach s slabs
    (setq cur  (assoc (caddr s) types)
          pcs  (mapcar '(lambda (p) (list (car p) (+ (nth 3 p) k) (+ (nth 4 p) k))) (cadr s))
          cands (sd:sort (vl-remove-if-not
                           '(lambda (tp) (and (/= (car tp) (car cur)) (/= (car tp) "MOI") (/= (nth 3 tp) 0)
                                              (< (* (nth 1 tp) (nth 2 tp)) (* (nth 1 cur) (nth 2 cur)))))
                           types)
                         '(lambda (a b) (< (* (nth 1 a) (nth 2 a)) (* (nth 1 b) (nth 2 b)))))
          done nil)
    (foreach tp cands
      (if (not done)
        (progn
          (setq res (sd:slab-pack pcs (list (list (car tp) (nth 1 tp) (nth 2 tp) 1 (nth 4 tp) (nth 5 tp) (nth 6 tp))) rot k 0 0 0 nil))
          (if (and (= (length (car res)) 1) (null (caddr res)))
            (setq out   (cons (car (car res)) out)
                  types (sd:add-type (sd:add-type types (car tp) -1) (car cur) 1)
                  done  t)))))
    (if (not done) (setq out (cons s out))))
  (list (reverse out) types))

;; ---- Toi uu kieu ABF cho SDDATHO: nhieu cach xep, uu tien tam du, leo doi ----
;; Cac o trong du lon (ca 2 canh >= dumin) cua 1 tam: ((x y rong cao) ...) kich thuoc that (tru be rong luoi cat)
(defun sd:sp-free (s k dumin / r)
  (foreach f (car s)
    (if (and (>= (- (nth 2 f) k) dumin) (>= (- (nth 3 f) k) dumin))
      (setq r (cons (list (nth 0 f) (nth 1 f) (- (nth 2 f) k) (- (nth 3 f) k)) r))))
  (reverse r))

;; Khoa so sanh: (vien-khong-xep so-tam-mua-moi dien-tich-tam-kho-dung -dien-tich-phe-lieu-giu-lai); nho hon la tot hon
(defun sd:sp-key (slabs types nof k dumin / nnew raw rem tp)
  (setq nnew 0 raw 0.0 rem 0.0)
  (foreach s slabs
    (setq tp (assoc (caddr s) types))
    (cond ((= (car tp) "MOI") (setq nnew (1+ nnew)))
          ((nth 6 tp))
          (t (setq raw (+ raw (* (nth 4 tp) (nth 5 tp))))))
    (foreach f (sd:sp-free s k dumin) (setq rem (+ rem (* (nth 2 f) (nth 3 f))))))
  (list (length nof) nnew raw (- rem)))
(defun sd:sp-less (a b)
  (cond ((/= (car a) (car b)) (< (car a) (car b)))
        ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
        ((> (abs (- (caddr a) (caddr b))) 1.0) (< (caddr a) (caddr b)))
        (t (< (cadddr a) (- (cadddr b) 20000.0)))))

;; Xep + doi tam; q: 0 nhanh (1 cach), 1 can bang (18 to hop: 3 thu tu x 3 cach tach x 2 cach chon tam; thu 48 to hop cho ket qua nhu nhau), 2 ky (them leo doi). Tra ve (slabs types nof)
(defun sd:slab-opt (pcs types rot k q uu dumin / sorts fms sms tms best bk ord s fm sm tm r1 r2 key cur curk n i j a b nb iter t0 bfm bsm btm bord seed)
  (setq q (cond (q) (0))
        sorts (if (= q 0) '(0) '(1 3 0))
        fms (if (= q 0) '(0) '(0))
        sms (if (= q 0) '(0) '(1 2 0))
        tms (if (= q 0) '(0) '(0 1)))
  (foreach s sorts
    (setq ord (sd:ng-sort pcs s))
    (foreach fm fms
      (foreach sm sms
        (foreach tm tms
          (setq r1 (sd:slab-pack ord types rot k fm sm tm uu)
                r2 (sd:downsize (car r1) (cadr r1) rot k)
                key (sd:sp-key (car r2) (cadr r2) (caddr r1) k dumin))
          (if (or (null bk) (sd:sp-less key bk))
            (setq best (list (car r2) (cadr r2) (caddr r1)) bk key bord ord bfm fm bsm sm btm tm))))))
  (if (and (>= q 2) (> (length pcs) 3))
    (progn
      (setq n (length bord) cur bord curk bk iter 0 seed 12345.0 t0 (getvar "MILLISECS"))
      (while (and (< iter 600) (< (- (getvar "MILLISECS") t0) 6000.0))
        (setq seed (rem (+ (* seed 1664525.0) 1013904223.0) 4294967296.0) i (fix (* n (/ seed 4294967296.0)))
              seed (rem (+ (* seed 1664525.0) 1013904223.0) 4294967296.0) j (fix (* n (/ seed 4294967296.0)))
              iter (1+ iter))
        (if (/= i j)
          (progn
            (setq a (nth i cur) b (nth j cur) nb (sd:lset (sd:lset cur i b) j a)
                  r1 (sd:slab-pack nb types rot k bfm bsm btm uu)
                  r2 (sd:downsize (car r1) (cadr r1) rot k)
                  key (sd:sp-key (car r2) (cadr r2) (caddr r1) k dumin))
            (if (not (sd:sp-less curk key))
              (progn (setq cur nb curk key)
                     (if (sd:sp-less key bk) (setq best (list (car r2) (cadr r2) (caddr r1)) bk key)))))))))
  best)

;; Them 1 tam du vao kho: cung vat lieu + kich thuoc (+-1 mm) + day thi cong so luong; ma moi = ma-goc-D<n> (khong lap ma da co)
(defun sd:sp-add-rem (inv parent mat w h thk / root e hit n id)
  (setq root (if (setq n (vl-string-search "-D" parent)) (substr parent 1 n) parent)
        e (assoc parent inv)
        thk (cond ((and e (> (nth 5 e) 0)) (nth 5 e)) (thk) (0.0)))
  (foreach x inv
    (if (and (nth 6 x) (= (nth 1 x) mat) (equal (nth 2 x) w 1.0) (equal (nth 3 x) h 1.0) (equal (nth 5 x) thk 0.5)) (setq hit x)))
  (if hit
    (subst (list (nth 0 hit) (nth 1 hit) (nth 2 hit) (nth 3 hit) (1+ (nth 4 hit)) (nth 5 hit) "R") hit inv)
    (progn
      (setq n 1 id (strcat root "-D1"))
      (while (assoc id inv) (setq n (1+ n) id (strcat root "-D" (itoa n))))
      (append inv (list (list id mat (float (fix (+ 0.5 w))) (float (fix (+ 0.5 h))) 1 thk "R"))))))

;; Tam du moi tu cac o trong: ((id-goc rong cao) ...) theo thu tu tam; id-goc = ma loai tam
(defun sd:sp-remnants (slabs k dumin / r)
  (foreach s slabs
    (foreach f (sd:sp-free s k dumin)
      (setq r (cons (list (caddr s) (nth 2 f) (nth 3 f)) r))))
  (reverse r))

;;; --------------------------------------------------------------------------
;;;  SDKHODA - Quan ly kho da tho: nhieu loai tam, kich thuoc, so luong
;;;  ban ghi kho: (ma-tam ma-VL dai rong so-luong day); ma-VL "*" = dung cho moi VL
;;; --------------------------------------------------------------------------
(defun sd:kho () (vlax-ldata-get "SD" "KHO"))

(defun sd:kho-print (inv)
  (princ "\n  Ma tam | Ma VL | Dai x Rong (mm) | SL | Day")
  (foreach e inv
    (princ (strcat "\n  " (nth 0 e) (if (nth 6 e) " (du)" "") " | " (nth 1 e) " | " (sd:num (nth 2 e)) " x " (sd:num (nth 3 e))
                   " | " (itoa (nth 4 e)) " | " (if (> (nth 5 e) 0) (sd:num (nth 5 e)) "-"))))
  (princ (strcat "\n  Tong: " (itoa (length inv)) " loai, "
                 (itoa (apply '+ (cons 0 (mapcar '(lambda (e) (nth 4 e)) inv)))) " tam, "
                 (sd:rtos (/ (apply '+ (cons 0.0 (mapcar '(lambda (e) (* (nth 2 e) (nth 3 e) (nth 4 e))) inv))) 1e6) 2)
                 " m2")))

(defun c:SDKHODA (/ inv op id e more fn f ln fl sep mode new)
  (sd:begin)
  (setq inv (sd:kho))
  (if (not (sd:dlg "Kho da tho (SDKHODA)"
                   (list (list "op" "Thao tac" 'kw "Lietke"
                               '(("Lietke" . "Liet ke kho") ("Them" . "Them loai tam") ("Sua" . "Sua so luong")
                                 ("Xoa" . "Xoa loai tam") ("Xoadu" . "Xoa tat ca tam du (phe lieu giu lai tu SDDATHO)")
                                 ("Nhap" . "Nhap tu CSV") ("Xuat" . "Xuat ra CSV"))))))
    (exit))
  (setq op (sd:v "op"))
  (cond
    ((= op "Them")
     (setq more t)
     (while more
       (if (not (sd:dlg "Them tam da tho vao kho (SDKHODA)"
                        (list (list "id" "Ma tam (vd T01)" 'str (strcat "T" (itoa (1+ (length inv)))))
                              (list "mat" "Dung cho ma vat lieu (* = moi vat lieu)" 'str "*")
                              (list "L" "Dai (mm)" 'real 2700.0)
                              (list "B" "Rong (mm)" 'real 1800.0)
                              (list "n" "So luong tam" 'int 1)
                              (list "t" "Chieu day (mm, 0 = khong kiem tra)" 'real0 0.0)
                              (list "more" "Them loai tam khac sau khi OK" 'tog nil))))
         (setq more nil)
         (progn
           (setq id (sd:v "id") more (sd:v "more"))
           (if (assoc id inv)
             (princ "\n[SD] Ma tam da co, dung lenh Sua de doi so luong.")
             (setq inv (append inv (list (list id (sd:v "mat") (sd:v "L") (sd:v "B") (sd:v "n") (sd:v "t"))))))))))
    ((= op "Sua")
     (sd:kho-print inv)
     (if (and inv
              (sd:dlg "Sua so luong tam (SDKHODA)"
                      (list (list "id" "Ma tam" 'kw (car (car inv))
                                  (mapcar '(lambda (x) (cons (car x) (strcat (car x) "  " (sd:num (nth 2 x)) "x"
                                                                             (sd:num (nth 3 x)) "  SL " (itoa (nth 4 x)))))
                                          inv))
                            (list "n" "So luong moi" 'int0 (nth 4 (car inv)))))
              (setq e (assoc (sd:v "id") inv)))
       (setq inv (subst (list (nth 0 e) (nth 1 e) (nth 2 e) (nth 3 e) (sd:v "n") (nth 5 e) (nth 6 e)) e inv))
       (princ "\n[SD] Kho trong hoac da huy.")))
    ((= op "Xoa")
     (sd:kho-print inv)
     (if (and inv
              (sd:dlg "Xoa tam khoi kho (SDKHODA)"
                      (list (list "id" "Ma tam can xoa" 'kw (car (car inv))
                                  (append (mapcar 'car inv) '(("*" . "* - xoa het kho")))))))
       (setq id (sd:v "id") inv (if (= id "*") nil (vl-remove (assoc id inv) inv)))))
    ((= op "Xoadu")
     (setq inv (vl-remove-if '(lambda (x) (nth 6 x)) inv))
     (princ "\n[SD] Da xoa cac tam du khoi kho."))
    ((= op "Nhap")
     (if (and (setq fn (getfiled "Chon file kho da tho (CSV: Ma tam;Ma VL;Dai;Rong;SL;Day;Loai = R neu la tam du)" (getvar "DWGPREFIX") "csv" 0))
              (setq f (sd:open fn "r")))
       (progn
         (setq mode (if (sd:dlg "Nhap kho tu CSV (SDKHODA)"
                                (list (list "mode" "Du lieu cu trong kho" 'kw "Themvao"
                                            '(("Themvao" . "Giu, them vao") ("Thaythe" . "Thay the toan bo")))))
                      (sd:v "mode") "Themvao"))
         (while (setq ln (read-line f))
           (setq sep (if (vl-string-search ";" ln) ";" ",")
                 fl  (mapcar '(lambda (x) (vl-string-trim " \t\"" x)) (sd:split ln sep)))
           (if (and (>= (length fl) 5) (> (atof (nth 2 fl)) 0) (> (atof (nth 3 fl)) 0))
             (setq new (cons (list (nth 0 fl) (if (= (nth 1 fl) "") "*" (nth 1 fl))
                                   (atof (nth 2 fl)) (atof (nth 3 fl)) (atoi (nth 4 fl))
                                   (if (nth 5 fl) (atof (nth 5 fl)) 0.0)
                                   (if (and (nth 6 fl) (= (strcase (nth 6 fl)) "R")) "R"))
                             new))))
         (setq fn (sd:close f))
         (setq inv (if (= mode "Thaythe") (reverse new)
                     (append (vl-remove-if '(lambda (x) (assoc (car x) new)) inv) (reverse new))))
         (princ (strcat "\n[SD] Da nhap " (itoa (length new)) " loai tam.")))))
    ((= op "Xuat")
     (setq fn (sd:csv-name "_KhoDaTho.csv"))
     (if (setq f (sd:open fn "w"))
       (progn
         (write-line "Ma tam;Ma VL;Dai (mm);Rong (mm);SL;Day (mm);Loai (R = tam du)" f)
         (foreach e inv
           (write-line (sd:join (list (nth 0 e) (nth 1 e) (sd:num (nth 2 e)) (sd:num (nth 3 e))
                                      (itoa (nth 4 e)) (sd:num (nth 5 e)) (if (nth 6 e) "R" "")) ";") f))
         (setq fn (sd:close f))
         (princ (strcat "\n[SD] Da xuat: " fn))))))
  (if (member op '("Them" "Sua" "Xoa" "Xoadu" "Nhap")) (vlax-ldata-put "SD" "KHO" inv))
  (sd:kho-print inv)
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDATHO - Cat vien tu da tho: kho nhieu kich thuoc hoac 1 co tam; so do cat
;;; --------------------------------------------------------------------------
(defun c:SDDATHO (/ ss grp inv src buy SL SB trim kerf rot ds mats pcs uniq slabs types res nof
                    lays key g pt x0 y0 col idx used fin tfin traw lines bx base rowh maxw th fn f tp thkM
                    usage moi moid uu giu dumin oq rems nrem remarea ntrem)
  (sd:begin)
  (if (not (setq ss (sd:select-tiles "\nChon cac vien can cat tu da tho <Enter = tat ca>: ")))
    (princ "\n[SD] Khong tim thay vien nao (SDGACH / SDCHANTUONG).")
    (progn
      (setq inv (sd:kho))
      (if inv (sd:kho-print inv))
      (if (not (sd:dlg "Cat vien tu da tho (SDDATHO)"
                       (list (list "src" "Nguon da tho" 'kw (if inv "Kho" "Motco")
                                   (if inv '(("Kho" . "Kho (nhieu co tam)") ("Motco" . "Mot co tam")) '(("Motco" . "Mot co tam"))))
                             (list "buy" "Khi kho khong du" 'kw "Muamoi" '(("Muamoi" . "Them tam mua moi") ("Dung" . "Bao thieu"))
                                   '("src" "Kho"))
                             (list "SL" "Tam da tho / tam mua moi - dai (mm)" 'real (sd:cfg "SLABL" 2700.0))
                             (list "SB" "Tam da tho / tam mua moi - rong (mm)" 'real (sd:cfg "SLABB" 1800.0))
                             (list "trim" "Xen bien moi canh (mm)" 'real0 (sd:cfg "SLABTRIM" 20.0))
                             (list "kerf" "Be rong luoi cat (mm)" 'real0 (sd:cfg "SLABKERF" 3.0))
                             (list "rot" "Cho xoay vien 90 do (khong giu chieu van)" 'tog t)
                             (list "ds" "Ty le ve so do cat 1/" 'int (cond (*SD:DTSC*) (50)))
                             (list "uu" "Uu tien dung tam du trong kho truoc" 'tog t nil '("src" "Kho"))
                             (list "giu" "Giu phe lieu (o trong du lon) thanh tam du trong kho" 'tog t nil '("src" "Kho"))
                             (list "dumin" "Tam du: chi giu khi ca 2 canh >= (mm)" 'real0 (sd:cfg "DUMIN" 300.0) nil '("src" "Kho"))
                             (list "oq" "Do ky khi xep (thu nhieu cach, chon it tam / it mua moi nhat)" 'kw (cond (*SD:DTQ*) ("Canbang"))
                                   '(("Nhanh" . "Nhanh: 1 cach xep") ("Canbang" . "Can bang: thu nhieu to hop sap xep / cham diem / tach o / chon tam")
                                     ("Ky" . "Ky: them leo doi hoan doi thu tu (toi da ~6 giay moi vat lieu)")))
                             (list "ded" "Tru so tam da dung khoi kho (va ghi tam du moi)" 'tog nil nil '("src" "Kho")))))
        (exit))
      (setq src (sd:v "src") buy (or (/= src "Kho") (= (sd:v "buy") "Muamoi"))
            SL (sd:cfg-put "SLABL" (sd:v "SL")) SB (sd:cfg-put "SLABB" (sd:v "SB"))
            trim (sd:cfg-put "SLABTRIM" (sd:v "trim")) kerf (sd:cfg-put "SLABKERF" (sd:v "kerf"))
            rot (sd:v "rot") ds (float (sd:v "ds")) *SD:DTSC* (fix ds)
            uu (sd:v "uu") giu (and (= src "Kho") (sd:v "giu")) dumin (sd:cfg-put "DUMIN" (sd:v "dumin"))
            oq (cond ((sd:v "oq")) ("Canbang")) *SD:DTQ* oq
            moi (if (= src "Kho") "MUA MOI" "TAM") moid (if (= src "Kho") "MUA M\\U+1EDAI" "T\\U+1EA4M")
            grp (sd:tile-groups ss))
      (foreach g grp (if (not (member (car (nth 3 g)) mats)) (setq mats (cons (car (nth 3 g)) mats))))
      (setq pt (sd:getpt "\nDiem chen so do cat (goc trai tren): " nil)
            y0 (if pt (cadr pt) 0.0) tfin 0.0 traw 0.0)
      (foreach mat (reverse mats)
        ;; vien rieng (ma w h SL), canh lon giam dan, roi trai ra tung vien
        (setq uniq nil pcs nil thkM nil)
        (foreach g grp
          (if (= (car (nth 3 g)) mat)
            (setq uniq (cons (list (nth 2 (nth 3 g)) (+ (nth 3 (nth 3 g)) kerf) (+ (nth 4 (nth 3 g)) kerf) (nth 1 g)) uniq)
                  thkM (cond (thkM) ((nth 11 (nth 3 g)))))))
        (setq uniq (sd:sort uniq '(lambda (a b) (if (equal (max (cadr a) (caddr a)) (max (cadr b) (caddr b)) 0.01)
                                                  (> (* (cadr a) (caddr a)) (* (cadr b) (caddr b)))
                                                  (> (max (cadr a) (caddr a)) (max (cadr b) (caddr b)))))))
        (foreach u uniq (repeat (cadddr u) (setq pcs (cons (list (car u) (cadr u) (caddr u)) pcs))))
        ;; loai tam dung duoc cho vat lieu nay (kho dung ma VL hoac "*", dung chieu day)
        (setq types nil)
        (if (= src "Kho")
          (foreach e inv
            (if (and (> (nth 4 e) 0) (or (= (nth 1 e) "*") (= (nth 1 e) mat))
                     (or (<= (nth 5 e) 0) (null thkM) (<= thkM 0) (equal (nth 5 e) thkM 0.5)))
              ;; tam du (R) da la canh cat sach: khong xen bien nua
              (setq types (cons (list (nth 0 e) (if (nth 6 e) (+ (nth 2 e) kerf) (+ (- (nth 2 e) trim trim) kerf))
                                      (if (nth 6 e) (+ (nth 3 e) kerf) (+ (- (nth 3 e) trim trim) kerf))
                                      (nth 4 e) (nth 2 e) (nth 3 e) (nth 6 e))
                                types)))))
        (if buy (setq types (cons (list "MOI" (+ (- SL trim trim) kerf) (+ (- SB trim trim) kerf) -1 SL SB nil) types)))
        (setq res   (sd:slab-opt (reverse pcs) types rot kerf (cond ((= oq "Nhanh") 0) ((= oq "Ky") 2) (t 1)) uu dumin)
              nof   (caddr res)
              slabs (car res)
              types (cadr res)
              fin   (apply '+ (mapcar '(lambda (s) (apply '+ (mapcar '(lambda (p) (* (nth 3 p) (nth 4 p))) (cadr s)))) slabs)))
        ;; cap nhat ton kho tam thoi (cho vat lieu sau) va thong ke su dung theo loai tam
        (setq usage nil)
        (foreach s slabs
          (setq usage (sd:addcnt (caddr s) 1 usage)))
        (if (= src "Kho")
          (setq inv (mapcar '(lambda (e) (if (assoc (car e) usage)
                                           (list (nth 0 e) (nth 1 e) (nth 2 e) (nth 3 e)
                                                 (- (nth 4 e) (cdr (assoc (car e) usage))) (nth 5 e))
                                           e))
                            inv)))
        (setq tfin (+ tfin fin)
              traw (+ traw (apply '+ (mapcar '(lambda (s) (setq tp (assoc (caddr s) types)) (* (nth 4 tp) (nth 5 tp))) slabs))))
        ;; phe lieu du lon -> tam du trong kho (cho lan chay sau); tam du da dung o lan nay khong tinh la phe lieu moi
        (if giu
          (progn
            (setq rems (sd:sp-remnants slabs kerf dumin) nrem 0 remarea 0.0)
            (foreach r rems
              (setq inv (sd:sp-add-rem inv (car r) mat (nth 1 r) (nth 2 r) thkM)
                    nrem (1+ nrem) remarea (+ remarea (* (nth 1 r) (nth 2 r)))))
            (setq ntrem (+ (cond (ntrem) (0)) nrem))
            (if (> nrem 0)
              (princ (strcat "\n   Giu lai " (itoa nrem) " tam du (" (sd:rtos (/ remarea 1e6) 2) " m2), moi canh >= " (sd:num dumin) " mm"
                             (if (sd:v "ded") " - ghi vao kho" " - CHUA ghi kho (bat 'Tru so tam da dung khoi kho')"))))))
        ;; gom so do giong nhau (cung loai tam + cung cach xep)
        (setq lays nil)
        (foreach s slabs
          (setq key (vl-princ-to-string (cons (caddr s) (cadr s))))
          (if (setq g (assoc key lays))
            (setq lays (subst (list key (1+ (cadr g)) (caddr g)) g lays))
            (setq lays (cons (list key 1 s) lays))))
        (setq lays (reverse lays))
        (princ (strcat "\n " mat ": " (itoa (length slabs)) " tam (" (itoa (length lays)) " mau so do)"))
        (foreach u usage
          (setq tp (assoc (car u) types))
          (princ (strcat "\n   " (if (= (car u) "MOI") moi (car u)) (if (nth 6 tp) " (tam du)" "") " " (sd:num (nth 4 tp)) "x" (sd:num (nth 5 tp))
                         ": " (itoa (cdr u)) " tam")))
        (if nof
          (princ (strcat "\n [!] Khong du da / vien qua lon, chua xep: " (itoa (length nof)) " vien ("
                         (sd:join (sd:uniq nof) ", ") ")")))
        ;; ve so do
        (if pt
          (progn
            (sd:text (list (car pt) y0)
                     (strcat "S\\U+01A0 \\U+0110\\U+1ED2 C\\U+1EAET \\U+0110\\U+00C1 TH\\U+00D4 " mat ": " (itoa (length slabs)) " t\\U+1EA5m; th\\U+00E0nh ph\\U+1EA9m "
                             (sd:rtos (/ fin 1e6) 2) " m\\U+00B2"
                             (if nof (strcat "; THI\\U+1EBEU \\U+0110\\U+00C1 CHO " (itoa (length nof)) " VI\\U+00CAN") ""))
                     (* 3.5 ds) "L" "SD-CHU")
            (setq y0 (- y0 (* 12 ds)) x0 (car pt) col 0 idx 0 rowh 0.0
                  maxw (* 3.5 (apply 'max (mapcar '(lambda (x) (nth 4 x)) types))))
            (foreach l lays
              (setq tp   (assoc (caddr (caddr l)) types)
                    idx  (1+ idx)
                    used (apply '+ (mapcar '(lambda (p) (* (nth 3 p) (nth 4 p))) (cadr (caddr l)))))
              (if (and (> col 0) (> (+ (- x0 (car pt)) (nth 4 tp)) maxw))
                (setq col 0 x0 (car pt) y0 (- y0 rowh (* 12 ds)) rowh 0.0))
              (setq bx x0 base (- y0 (nth 5 tp)) rowh (max rowh (nth 5 tp)))
              (sd:rect (list bx base 0.0) (nth 4 tp) (nth 5 tp) "SD-GIACONG")
              (sd:rect (list (+ bx trim) (+ base trim) 0.0)
                       (- (nth 4 tp) trim trim) (- (nth 5 tp) trim trim) "SD-KHUAT")
              (foreach p (cadr (caddr l))
                (setq th (max (* 0.6 ds) (min (* 2.0 ds) (* 0.25 (min (nth 3 p) (nth 4 p))))))
                (sd:rect (list (+ bx trim (nth 1 p)) (+ base trim (nth 2 p)) 0.0) (nth 3 p) (nth 4 p) "SD-GACH-CAT")
                (sd:text (list (+ bx trim (nth 1 p) (/ (nth 3 p) 2)) (+ base trim (nth 2 p) (/ (nth 4 p) 2) (* 0.6 th)))
                         (car p) th "MC" "SD-CHU")
                (sd:text (list (+ bx trim (nth 1 p) (/ (nth 3 p) 2)) (- (+ base trim (nth 2 p) (/ (nth 4 p) 2)) (* 0.6 th)))
                         (strcat (sd:rtos (nth 3 p) 0) "\\U+00D7" (sd:rtos (nth 4 p) 0)) (* 0.8 th) "MC" "SD-CHU")
                (setq lines (cons (sd:join (list mat (itoa idx) (if (= (car tp) "MOI") moi (car tp))
                                                 (sd:num (nth 4 tp)) (sd:num (nth 5 tp)) (itoa (cadr l)) (car p)
                                                 (sd:rtos (nth 1 p) 0) (sd:rtos (nth 2 p) 0)
                                                 (sd:rtos (nth 3 p) 0) (sd:rtos (nth 4 p) 0)
                                                 (if (= (nth 5 p) 1) "Co" "Khong")) ";")
                                  lines)))
              (sd:text (list bx (+ y0 (* 2 ds)))
                       (strcat "T\\U+1EA4M " (itoa idx) " (\\U+00D7" (itoa (cadr l)) ") "
                               (if (= (car tp) "MOI") moid (car tp)) " " (sd:num (nth 4 tp)) "\\U+00D7" (sd:num (nth 5 tp))
                               " - s\\U+1EED d\\U+1EE5ng " (sd:rtos (/ (* 100.0 used) (* (nth 4 tp) (nth 5 tp))) 1) "%")
                       (* 2.5 ds) "L" "SD-CHU")
              (setq col (1+ col) x0 (+ x0 (nth 4 tp) (* 0.15 (nth 4 tp)))))
            (setq y0 (- y0 rowh (* 20 ds))))))
      (princ (strcat "\n TONG: da tho " (sd:rtos (/ traw 1e6) 2) " m2, thanh pham " (sd:rtos (/ tfin 1e6) 2)
                     " m2, hieu suat " (sd:rtos (if (> traw 0) (/ (* 100.0 tfin) traw) 0.0) 1) "%"))
      ;; tru kho
      (if (= src "Kho")
        (progn
          (if (sd:v "ded")
            (progn
              (vlax-ldata-put "SD" "KHO" (vl-remove-if '(lambda (e) (<= (nth 4 e) 0)) inv))
              (princ "\n[SD] Da cap nhat kho (loai tam het hang duoc xoa).")
              (sd:kho-print (sd:kho))))))
      (setq fn (sd:csv-name "_SoDoCatDaTho.csv"))
      (if (and lines (setq f (sd:open fn "w")))
        (progn
          (write-line "Ma VL;Mau so do;Loai tam;Dai tam;Rong tam;So tam;Ma vien;x (mm);y (mm);Rong (mm);Cao (mm);Xoay" f)
          (foreach l (reverse lines) (write-line l f))
          (setq fn (sd:close f))
          (princ (strcat "\n[SD] Da xuat: " fn))))))
  (sd:finish))

(defun sd:uniq (lst / r) (foreach x lst (if (not (member x r)) (setq r (cons x r)))) (reverse r))

;;; ==========================================================================
;;;  SDTHANGDA - Cau thang da: mat bac, co bac, mui bac, khe LED, len chan tuong, ra da kieu ABF
;;;  Mui bac: Thang (mat chong len co, mui nho ra) / V45 (mat va co ghep vat 45 do) /
;;;           Roi (dai mui cat rieng) / CNC (mat lien, mui bo hay vat bang CNC)
;;;  Khe LED: Cobac (tru vao chieu cao co bac) / Matbac (tru vao chieu sau mat bac) / Ranh (cat ranh duoi mat bac)
;;; ==========================================================================
;; So phan chia chieu dai L thanh cac vien dai nhat Lmax (co mach gap giua cac vien)
(defun sd:st-split (L Lmax gap)
  (max 1 (fix (+ (/ (+ L gap) (+ Lmax gap)) 0.999999))))

;; Danh sach vien cua 1 cau thang. Moi vien: (ma ten dai rong so-luong day goc ghichu vat-mm cnc-mm)
;; dai x rong la kich thuoc phoi (mat lon nhat cua vien vat 45), goc la goc cat dac biet (90 = vuong)
(defun sd:st-pieces (kieu n W gd R tm tc nho rm led ledv Lmax gap nside hl
                     / k part dm hc pcs ls al blank m seg cnc)
  (setq nho (if (= kieu "V45") 0.0 nho)
        dm  (cond ((= kieu "V45") gd) ((= kieu "Roi") (- (+ gd nho) rm)) (t (+ gd nho)))
        hc  (if (= kieu "V45") R (- R tm)))
  (if (> led 0.0)
    (cond ((= ledv "Cobac") (setq hc (- hc led)))
          ((= ledv "Matbac") (setq dm (- dm led)))))
  (setq k (sd:st-split W Lmax gap)
        part (/ (- W (* (1- k) gap)) k)
        cnc (cond ((= kieu "CNC") part) (t 0.0)))
  (if (or (and (> led 0.0) (= ledv "Ranh")) (= ledv "Hoc")) (setq cnc (+ cnc part)))
  (setq pcs
        (list (list "MB" "Mat bac" part dm (* n k) tm (if (= kieu "V45") 45.0 90.0)
                    (cond ((= kieu "V45") "vat 45 do canh truoc")
                          ((= kieu "CNC") "mui bo / vat CNC")
                          ((= kieu "Roi") "mat bac, mui rieng")
                          (t "mui nho ra"))
                    (if (= kieu "V45") part 0.0) cnc)
              (list "CB" "Co bac" part hc (* n k) tc (if (= kieu "V45") 45.0 90.0)
                    (if (= kieu "V45") "vat 45 do canh tren" "cat vuong")
                    (if (= kieu "V45") part 0.0) 0.0)))
  (if (= ledv "Hoc")
    (setq pcs (cons (sd:lset (car pcs) 7 (strcat (nth 7 (car pcs)) ", hoc LED duoi mep truoc")) (cdr pcs))))
  (if (= kieu "Roi")
    (setq pcs (append pcs (list (list "MR" "Dai mui roi" part rm (* n k) tm 90.0 "bo / vat CNC canh truoc" 0.0 part)))))
  (if (and (> nside 0) (> hl 0.0))
    (progn
      (setq ls (* n (sqrt (+ (* gd gd) (* R R))))
            al (atan R gd)
            blank (+ ls (* hl (/ (sin al) (cos al))))
            m (sd:st-split blank Lmax gap)
            seg (/ (- blank (* (1- m) gap)) m))
      (setq pcs (append pcs (list (list "LN" "Len chan tuong" seg hl (* m nside) tc (* al (/ 180.0 pi))
                                        "2 vien dau cuoi cat xien theo do doc" 0.0 0.0))))))
  pcs)

;; ---- Phoi bac quat theo hinh that: bao loi, phoi chu nhat nho nhat (xoay), ghep 2 vien nguoc nhau ----
(defun sd:cr (o a b) (- (* (- (car a) (car o)) (- (cadr b) (cadr o))) (* (- (cadr a) (cadr o)) (- (car b) (car o)))))

;; Bao loi (monotone chain) cua cac diem 2D, tra ve cac dinh nguoc kim dong ho
(defun sd:hull (pts / s lo up)
  (setq s (sd:sort pts '(lambda (a b) (if (= (car a) (car b)) (< (cadr a) (cadr b)) (< (car a) (car b))))))
  (foreach p s
    (while (and (cdr lo) (<= (sd:cr (cadr lo) (car lo) p) 0.0)) (setq lo (cdr lo)))
    (setq lo (cons p lo)))
  (foreach p (reverse s)
    (while (and (cdr up) (<= (sd:cr (cadr up) (car up) p) 0.0)) (setq up (cdr up)))
    (setq up (cons p up)))
  (append (reverse (cdr lo)) (reverse (cdr up))))

;; Rong x cao cua khung bao khi xoay he truc di phi
(defun sd:wf-bbox (pts phi / c sn xs ys)
  (setq c (cos phi) sn (sin phi)
        xs (mapcar '(lambda (p) (+ (* (car p) c) (* (cadr p) sn))) pts)
        ys (mapcar '(lambda (p) (- (* (cadr p) c) (* (car p) sn))) pts))
  (list (- (apply 'max xs) (apply 'min xs)) (- (apply 'max ys) (apply 'min ys))))

;; Phoi chu nhat dien tich nho nhat khi xoay mot da giac: (dien-tich rong cao goc-xoay)
(defun sd:wf-single (pts / k phi bb best a)
  (setq k 0)
  (while (< k 90)
    (setq phi (* k (/ pi 90.0)) bb (sd:wf-bbox pts phi) a (* (car bb) (cadr bb)))
    (if (or (null best) (< a (car best))) (setq best (list a (car bb) (cadr bb) phi)))
    (setq k (1+ k)))
  best)

;; Ghep 2 vien loi giong nhau, vien thu 2 xoay 180 do: B = t - A khong chong A khi t nam tren bien cua 2A.
;; Tra ve phoi chu nhat nho nhat cua cap, chua khe m giua 2 vien: (dien-tich rong cao goc-xoay tx ty)
(defun sd:wf-pair (hull m / best i p q s tt pts2 phi bb a dx dy ln)
  (setq i 0)
  (foreach p hull
    (setq q (nth (rem (1+ i) (length hull)) hull) s 0
          dx (- (car q) (car p)) dy (- (cadr q) (cadr p)) ln (max 1e-9 (sqrt (+ (* dx dx) (* dy dy)))))
    (while (<= s 10)
      (setq tt (list (+ (* 2.0 (+ (car p) (* (/ s 10.0) dx))) (* m (/ dy ln)))
                     (- (* 2.0 (+ (cadr p) (* (/ s 10.0) dy))) (* m (/ dx ln))))
            pts2 (append hull (mapcar '(lambda (a) (list (- (car tt) (car a)) (- (cadr tt) (cadr a)))) hull)) phi 0.0)
      (while (< phi pi)
        (setq bb (sd:wf-bbox pts2 phi) a (* (car bb) (cadr bb)))
        (if (or (null best) (< a (car best))) (setq best (list a (car bb) (cadr bb) phi (car tt) (cadr tt))))
        (setq phi (+ phi (/ pi 60.0))))
      (setq s (1+ s)))
    (setq i (1+ i)))
  best)

;; Bo vien cua ca cau thang: nve ve thang (moi ve n bac), chieu nghi cnl x cnw, nq bac quat tong goc gq (do), ban kinh trong ri / ngoai ro
(defun sd:st-all (kieu n W gd R tm tc nho rm led ledv Lmax gap nside hl nve cnl cnw nq gq ri ro dq rc dk / pcs out kl kw th hc ar hl1 b1 b2 np nr ky cc cl sg m ph)
  (setq pcs (sd:st-pieces kieu n W gd R tm tc nho rm led ledv Lmax gap nside hl)
        out (mapcar '(lambda (p) (if (> nve 1) (append (list (car p) (cadr p) (caddr p) (cadddr p) (* (nth 4 p) nve)) (nthcdr 5 p)) p)) pcs))
  (if (and (> nve 1) (> cnl 0.0) (> cnw 0.0))
    (progn
      (setq kl (sd:st-split cnl Lmax gap) kw (sd:st-split cnw Lmax gap))
      (setq out (append out (list (list "CN" "Chieu nghi" (/ (- cnl (* (1- kl) gap)) kl) (/ (- cnw (* (1- kw) gap)) kw)
                                        (* (1- nve) kl kw) tm 90.0 "tam lat chieu nghi" 0.0 0.0))))))
  (if (and (> nq 0) (> gq 0.0) (> ro ri))
    (progn
      (setq th (/ (* gq (/ pi 180.0)) nq)
            hc (- R (if (= kieu "V45") 0.0 tm))
            ar (* 0.5 th (- (* ro ro) (* ri ri)))
            ky (list th ri ro))
      (if (setq cc (assoc ky *SD:WFC*))
        (setq b1 (cadr cc) b2 (caddr cc))
        (progn
          (setq hl1 (sd:hull (sd:st-sector (list 0.0 0.0) ri ro (/ th -2.0) (/ th 2.0)))
                b1 (sd:wf-single hl1) b2 (sd:wf-pair hl1 (+ gap 2.0))
                *SD:WFC* (cons (list ky b1 b2) *SD:WFC*))))
      (setq
            np (if (< (car b2) (* 0.97 2.0 (car b1))) (fix (/ nq 2)) 0)
            nr (- nq (* 2 np)))
      (if (> nr 0)
        (setq out (append out (list (list "MQ" "Mat bac quat" (cadr b1) (caddr b1) nr tm (/ (* th 180.0) pi)
                                          "hinh quat: phoi chu nhat nho nhat khi xoay" 0.0 0.0 ar)))))
      (if (> np 0)
        (setq out (append out (list (list "MQG" "Mat bac quat ghep doi" (cadr b2) (caddr b2) np tm (/ (* th 180.0) pi)
                                          "2 quat xoay nguoc nhau trong 1 phoi" 0.0 0.0 (* 2.0 ar))))))
      (cond
        ;; co bac cong: tam cong cat tu phoi day bang CNC; phoi = day cung x rong day, day phoi = mui ten cung + day tam
        ((and (= dq "Cong") (> rc 1.0))
         (setq cl (* 2.0 rc (sin (/ th 2.0))) sg (* rc (- 1.0 (cos (/ th 2.0)))))
         (setq out (append out (list (list "CQC" "Co bac quat cong" cl hc nq (+ sg tc) (/ (* th 90.0) pi)
                                           (strcat "cong ban kinh " (sd:num rc) ", phoi day " (sd:rtos (+ sg tc) 0) " (CNC cat cong 2 mat)")
                                           0.0 (* 2.0 rc th) (* rc th hc))))))
        ;; co bac ghep doan: cac tam thang, hai dau vat nua goc chuyen huong
        ((and (= dq "Doan") (> rc 1.0) (> dk 1.0))
         (setq m (max 1 (fix (+ 0.999999 (/ (* rc th) dk)))) ph (/ th m))
         (setq out (append out (list (list "CQD" "Co bac quat ghep doan" (* 2.0 rc (sin (/ ph 2.0))) hc (* nq m) tc (/ (* ph 90.0) pi)
                                           (strcat "ghep " (itoa m) " doan / bac, 2 dau vat " (sd:rtos (/ (* ph 90.0) pi) 1) " do")
                                           (* 2.0 hc) 0.0 (* rc th hc (/ 1.0 m)))))))
        (t (setq out (append out (list (list "CQ" "Co bac quat" (- ro ri) hc nq tc 90.0 "canh truoc theo ban kinh" 0.0 0.0))))))))
  out)

;; Xep cac vien len tam da tho (kieu ABF) theo tung do day. Tra ve ((day slabs types nof) ...)
(defun sd:st-nest (pcs SL SB trim kerf rot q / out thks items types r)
  (foreach p pcs (if (not (member (nth 5 p) thks)) (setq thks (cons (nth 5 p) thks))))
  (foreach th (reverse thks)
    (setq items nil)
    (foreach p pcs
      (if (equal (nth 5 p) th 0.01)
        (repeat (fix (+ 0.5 (nth 4 p)))
          (setq items (cons (list (car p) (+ (nth 2 p) kerf) (+ (nth 3 p) kerf)) items)))))
    (setq types (list (list "MOI" (+ (- SL trim trim) kerf) (+ (- SB trim trim) kerf) -1 SL SB nil))
          r (sd:slab-opt (reverse items) types rot kerf q nil 0.0)
          out (cons (list th (car r) (cadr r) (caddr r)) out)))
  (reverse out))

;; Tom tat ket qua xep: (so-tam dien-tich-tho dien-tich-thanh-pham so-vien-chua-xep)
(defun sd:st-sum (nest / ns raw fin nof)
  (setq ns 0 raw 0.0 fin 0.0 nof 0)
  (foreach g nest
    (foreach s (cadr g)
      (setq ns (1+ ns)
            raw (+ raw (* (nth 4 (assoc (caddr s) (caddr g))) (nth 5 (assoc (caddr s) (caddr g)))))
            fin (+ fin (apply '+ (mapcar '(lambda (p) (* (nth 3 p) (nth 4 p))) (cadr s))))))
    (setq nof (+ nof (length (cadddr g)))))
  (list ns raw fin nof))

;; Tong dien tich phoi / chieu dai vat 45 / chieu dai CNC cua 1 bo vien (m2, m, m)
(defun sd:st-tot (pcs / a v c f)
  (setq a 0.0 v 0.0 c 0.0 f 0.0)
  (foreach p pcs
    (setq a (+ a (/ (* (nth 4 p) (nth 2 p) (nth 3 p)) 1e6))
          f (+ f (/ (* (nth 4 p) (cond ((nth 10 p)) (t (* (nth 2 p) (nth 3 p))))) 1e6))
          v (+ v (/ (* (nth 4 p) (nth 8 p)) 1000.0))
          c (+ c (/ (* (nth 4 p) (nth 9 p)) 1000.0))))
  (list a v c f))

;; Mat cat doc 3 bac de xem mui bac va khe LED. o = goc duoi trai, huong len cao di sang phai
(defun sd:st-profile (o kieu gd R tm tc nho rm led ledv ledr leds ledc / k x0 y0 hc dm tl tr hx hy)
  (setq nho (if (= kieu "V45") 0.0 nho)
        hc  (if (= kieu "V45") R (- R tm)))
  (if (and (> led 0.0) (= ledv "Cobac")) (setq hc (- hc led)))
  (setq k 0)
  (repeat 3
    (setq x0 (* k gd) y0 (* k R)
          tl (if (= kieu "Roi") (+ (- x0 nho) rm) (- x0 nho))
          tr (if (and (> led 0.0) (= ledv "Matbac")) (- (+ x0 gd) led) (+ x0 gd)))
    ;; co bac
    (if (= kieu "V45")
      (sd:pline (list (sd:p+ o x0 y0) (sd:p+ o (+ x0 tc) y0) (sd:p+ o (+ x0 tc) (+ y0 (- hc tc))) (sd:p+ o x0 (+ y0 hc))) t "SD-GACH")
      (sd:pline (list (sd:p+ o x0 y0) (sd:p+ o (+ x0 tc) y0) (sd:p+ o (+ x0 tc) (+ y0 hc)) (sd:p+ o x0 (+ y0 hc))) t "SD-GACH"))
    ;; mat bac (dinh tai y0 + R)
    (if (= kieu "V45")
      (sd:pline (list (sd:p+ o x0 (+ y0 R)) (sd:p+ o tr (+ y0 R)) (sd:p+ o tr (+ y0 (- R tm))) (sd:p+ o (+ x0 tm) (+ y0 (- R tm)))) t "SD-GACH-CAT")
      (sd:pline (list (sd:p+ o tl (+ y0 (- R tm))) (sd:p+ o tr (+ y0 (- R tm))) (sd:p+ o tr (+ y0 R)) (sd:p+ o tl (+ y0 R))) t "SD-GACH-CAT"))
    ;; hoc LED duoi mep truoc mat bac: hinh chu nhat cat vao mat bac + ky hieu den (layer SD-LED)
    (if (= ledv "Hoc")
      (progn
        (sd:make-layer "SD-LED" 1 "Continuous" 25)
        (setq hx (+ tl ledc) hy (+ y0 (- R tm)))
        (sd:pline (list (sd:p+ o hx hy) (sd:p+ o (+ hx ledr) hy) (sd:p+ o (+ hx ledr) (+ hy leds)) (sd:p+ o hx (+ hy leds))) t "SD-KHUAT")
        (if (= k 0)
          (progn
            (entmake (list '(0 . "CIRCLE") '(8 . "SD-LED") (cons 10 (sd:p+ o (+ hx (/ ledr 2.0)) (+ hy (/ leds 2.0)))) (cons 40 (* 0.3 (min ledr leds)))))
            (sd:line (sd:p+ o (+ hx (/ ledr 2.0)) (- hy 8.0)) (sd:p+ o (+ hx (/ ledr 2.0)) (+ hy leds 8.0)) "SD-LED")
            (sd:line (sd:p+ o (- hx 8.0) (+ hy (/ leds 2.0))) (sd:p+ o (+ hx ledr 8.0) (+ hy (/ leds 2.0))) "SD-LED")
            (sd:text (sd:p+ o (+ hx ledr 14.0) (- hy 10.0)) (strcat "HOC LED " (sd:num ledr) "x" (sd:num leds) ", cach mep " (sd:num ledc)) 6.0 "L" "SD-LED")))))
    ;; dai mui roi
    (if (= kieu "Roi")
      (sd:pline (list (sd:p+ o (- x0 nho) (+ y0 (- R tm))) (sd:p+ o tl (+ y0 (- R tm))) (sd:p+ o tl (+ y0 R)) (sd:p+ o (- x0 nho) (+ y0 R))) t "SD-KHUAT"))
    (setq k (1+ k))))

;; Mo ta ngan 1 phuong an
(defun sd:st-name (kieu)
  (cond ((= kieu "Thang") "Thang (mui nho ra)")
        ((= kieu "V45") "Ghep vat 45 do")
        ((= kieu "Roi") "Dai mui roi")
        (t "Mui bo / vat CNC")))

;; ---- Mat bang cau thang (hinh thang nhanh de doi chieu): ve, chieu nghi, bac quat ----
(defun sd:pp (p u d) (list (+ (car p) (* d (car u))) (+ (cadr p) (* d (cadr u)))))

;; Quat tu tam c, ban kinh trong r0 / ngoai r1, tu goc a0 den a1 (rad): da giac
(defun sd:st-sector (c r0 r1 a0 a1 / pts k m)
  (setq m 6 k 0)
  (while (<= k m)
    (setq pts (cons (sd:pp c (list (cos (+ a0 (* k (/ (- a1 a0) m)))) (sin (+ a0 (* k (/ (- a1 a0) m))))) r1) pts) k (1+ k)))
  (setq k m)
  (if (> r0 1.0)
    (while (>= k 0)
      (setq pts (cons (sd:pp c (list (cos (+ a0 (* k (/ (- a1 a0) m)))) (sin (+ a0 (* k (/ (- a1 a0) m))))) r0) pts) k (1- k)))
    (setq pts (cons c pts)))
  (reverse pts))

;; Hinh mat bang: danh sach ('P pts lay) polyline kin, ('L p1 p2 lay) doan, ('T p chu); toa do cuc bo, bac dau tai goc 0,0, huong +X.
;; dang "L" re trai moi lan re / "U" quay dau; chieu nghi cnl x cnw (0 = o vuong W x W, U: W x (2W + 50)); bac quat chi o lan re dau
(defun sd:st-plan (n gd W nve dang cnl cnw nq gq ri ro / out p u v k len a b c d i s th a0 j u2 p2 cl cw)
  (setq p (list 0.0 0.0) u (list 1.0 0.0) k 0 len (* n gd))
  (while (< k nve)
    (setq v (list (- (cadr u)) (car u)) a p b (sd:pp a u len) c (sd:pp b v W) d (sd:pp a v W))
    (setq out (cons (list 'P (list a b c d) "SD-GACH") out) i 1)
    (while (< i n)
      (setq out (cons (list 'L (sd:pp a u (* i gd)) (sd:pp (sd:pp a u (* i gd)) v W) "SD-GACH-VIEN") out) i (1+ i)))
    (setq out (cons (list 'T (sd:pp (sd:pp a u (/ len 2.0)) v (/ W 2.0)) (strcat "VE " (itoa (1+ k)) ": " (itoa n) " BAC")) out))
    (if (or (< (1+ k) nve) (and (= nve 1) (> nq 0) (= k 0)))
      (progn
        (cond
          ;; bac quat o lan re trai dau tien
          ((and (> nq 0) (= k 0) (/= dang "U"))
           (setq s ro th (/ (* gq (/ pi 180.0)) nq) a0 (- (atan (cadr u) (car u)) (/ pi 2.0)) j 0)
           (while (< j nq)
             (setq out (cons (list 'P (sd:st-sector (sd:pp b v s) ri s (+ a0 (* j th)) (+ a0 (* (1+ j) th))) "SD-GACH-CAT") out) j (1+ j)))
           (setq out (cons (list 'T (sd:pp (sd:pp b v (/ s 2.0)) u (/ s 2.0)) (strcat (itoa nq) " BAC QUAT")) out)
                 p2 (sd:pp (sd:pp b u s) v s) u2 v))
          ((= dang "U")
           (setq cl (if (> cnl 0.0) cnl W) cw (if (> cnw 0.0) cnw (+ (* 2.0 W) 50.0)))
           (setq out (cons (list 'P (list b (sd:pp b u cl) (sd:pp (sd:pp b u cl) v cw) (sd:pp b v cw)) "SD-GACH-CAT") out)
                 out (cons (list 'T (sd:pp (sd:pp b u (/ cl 2.0)) v (/ cw 2.0)) "CHIEU NGHI") out)
                 p2 (sd:pp b v cw) u2 (list (- (car u)) (- (cadr u)))))
          (t
           (setq cl (if (> cnl 0.0) cnl W) cw (if (> cnw 0.0) cnw W))
           (setq out (cons (list 'P (list b (sd:pp b u cl) (sd:pp (sd:pp b u cl) v cw) (sd:pp b v cw)) "SD-GACH-CAT") out)
                 out (cons (list 'T (sd:pp (sd:pp b u (/ cl 2.0)) v (/ cw 2.0)) "CHIEU NGHI") out)
                 p2 (sd:pp (sd:pp b u cl) v cw) u2 v)))
        (setq p p2 u u2)))
    (setq k (1+ k)))
  (reverse out))

;; Khung bao cac phan tu mat bang: ((xmin ymin) (xmax ymax))
(defun sd:st-pbb (items / pts)
  (foreach it items
    (cond ((= (car it) 'P) (setq pts (append pts (cadr it))))
          ((= (car it) 'L) (setq pts (append pts (list (cadr it) (caddr it)))))
          (t (setq pts (append pts (list (cadr it)))))))
  (sd:bbox pts))

(defun sd:st-pdraw (items dx dy ds)
  (foreach it items
    (cond ((= (car it) 'P) (sd:pline (mapcar '(lambda (q) (list (+ dx (car q)) (+ dy (cadr q)) 0.0)) (cadr it)) t (caddr it)))
          ((= (car it) 'L) (sd:line (list (+ dx (car (cadr it))) (+ dy (cadr (cadr it))) 0.0) (list (+ dx (car (caddr it))) (+ dy (cadr (caddr it))) 0.0) (cadddr it)))
          (t (sd:text (list (+ dx (car (cadr it))) (+ dy (cadr (cadr it))) 0.0) (caddr it) (* 2.5 ds) "MC" "SD-CHU")))))

(defun c:SDTHANGDA (/ mat n W gd R tm tc kieu nho rm led ledv Lmax gap nside hl SL SB trim kerf rot q pcs nest sm tot
                      cmp k pc pn sm2 tt pt ds y0 x0 i l key lays g tp bx base rowh col maxw idx used th lines fn f
                      thks e vb Htot nve cnl cnw nq gq ri ro nst cmf dang plan bb dq rc dk ledr leds ledc)
  (sd:begin)
  (if (not (sd:dlg "Cau thang da (SDTHANGDA)"
                   (list (list "mat" "Ma vat lieu" 'str (sd:cfg "ST-MAT" "DA"))
                         (list "n" "So bac (moi ve thang)" 'int (sd:cfg "ST-N" 16))
                         (list "W" "Be rong bac (mm)" 'real (sd:cfg "ST-W" 1200.0))
                         (list "gd" "Buoc dap - mat ngoai co bac nay den co bac ke (mm)" 'real (sd:cfg "ST-T" 280.0))
                         (list "R" "Chieu cao bac (mm)" 'real (sd:cfg "ST-R" 165.0))
                         (list "tm" "Day mat bac (mm)" 'real (sd:cfg "ST-TM" 30.0))
                         (list "tc" "Day co bac / len (mm)" 'real (sd:cfg "ST-TC" 20.0))
                         (list "kieu" "Kieu mui bac" 'kw (sd:cfg "ST-KIEU" "Thang")
                               '(("Thang" . "Thang: mat chong len co, mui nho ra")
                                 ("V45" . "V45: mat va co ghep vat 45 do")
                                 ("Roi" . "Roi: dai mui cat rieng")
                                 ("CNC" . "CNC: mat lien, mui bo / vat bang CNC")))
                         (list "nho" "Mui nho ra khoi mat co bac (mm)" 'real0 (sd:cfg "ST-NHO" 30.0)
                               nil '("kieu" "Thang" "Roi" "CNC"))
                         (list "rm" "Dai mui roi - be rong (mm)" 'real (sd:cfg "ST-RM" 50.0) nil '("kieu" "Roi"))
                         (list "led" "Khe hat LED (mm, 0 = khong)" 'real0 (sd:cfg "ST-LED" 0.0))
                         (list "ledv" "Khe LED tru vao" 'kw (sd:cfg "ST-LEDV" "Cobac")
                               '(("Cobac" . "Chieu cao co bac")
                                 ("Matbac" . "Chieu sau mat bac")
                                 ("Ranh" . "Khong tru, cat ranh duoi mat bac (CNC)")
                                 ("Hoc" . "Hoc LED duoi mep truoc mat bac (CNC, khong tru kich thuoc)")))
                         (list "ledr" "Hoc LED - rong (mm)" 'real (sd:cfg "ST-LEDR" 17.0) nil '("ledv" "Hoc"))
                         (list "leds" "Hoc LED - sau vao mat bac (mm)" 'real (sd:cfg "ST-LEDS" 20.0) nil '("ledv" "Hoc"))
                         (list "ledc" "Hoc LED - cach mep truoc mat bac (mm)" 'real0 (sd:cfg "ST-LEDC" 20.0) nil '("ledv" "Hoc"))
                         (list "nside" "Len chan tuong - so ben (0 = khong)" 'int0 (sd:cfg "ST-NSIDE" 2))
                         (list "hl" "Len chan tuong - be rong dai (mm)" 'real0 (sd:cfg "ST-HL" 100.0))
                         (list "Lmax" "Vien dai toi da (mm, dai hon se chia)" 'real (sd:cfg "ST-LMAX" 2400.0))
                         (list "gap" "Mach giua cac vien chia (mm)" 'real0 (sd:cfg "ST-GAP" 2.0))
                         (list "Htot" "Tong chieu cao thang (mm, 0 = nhap chieu cao bac)" 'real0 (sd:cfg "ST-H" 0.0))
                         (list "nve" "So ve thang (2 = chu L / chu U, moi ve 'So bac' bac)" 'int (sd:cfg "ST-NVE" 1))
                         (list "dang" "Hinh thang khi nhieu ve" 'kw (sd:cfg "ST-DANG" "L")
                               '(("L" . "Chu L: re trai moi lan re") ("U" . "Chu U: quay dau o chieu nghi")))
                         (list "cnl" "Chieu nghi - dai (mm, 0 = khong)" 'real0 (sd:cfg "ST-CNL" 0.0))
                         (list "cnw" "Chieu nghi - rong (mm)" 'real0 (sd:cfg "ST-CNW" 0.0))
                         (list "nq" "So bac quat (0 = khong)" 'int0 (sd:cfg "ST-NQ" 0))
                         (list "gq" "Bac quat - tong goc quay (do)" 'real0 (sd:cfg "ST-GQ" 90.0))
                         (list "ri" "Bac quat - ban kinh trong (mm)" 'real0 (sd:cfg "ST-RI" 50.0))
                         (list "ro" "Bac quat - ban kinh ngoai (mm)" 'real (sd:cfg "ST-RO" 1200.0))
                         (list "dq" "Co bac quat" 'kw (sd:cfg "ST-DQ" "Thang")
                               '(("Thang" . "Thang: tam thang theo canh truoc (ban kinh)")
                                 ("Cong" . "Cong: tam cong cat tu phoi day bang CNC")
                                 ("Doan" . "Doan: ghep cac tam thang theo cung")))
                         (list "rc" "Co bac quat cong - ban kinh cung (mm)" 'real (sd:cfg "ST-RC" 1200.0) nil '("dq" "Cong" "Doan"))
                         (list "dk" "Co bac quat ghep doan - rong toi da 1 doan (mm)" 'real (sd:cfg "ST-DK" 250.0) nil '("dq" "Doan"))
                         (list "SL" "Tam da tho - dai (mm)" 'real (sd:cfg "SLABL" 2700.0))
                         (list "SB" "Tam da tho - rong (mm)" 'real (sd:cfg "SLABB" 1800.0))
                         (list "trim" "Xen bien moi canh (mm)" 'real0 (sd:cfg "SLABTRIM" 20.0))
                         (list "kerf" "Be rong luoi cat (mm)" 'real0 (sd:cfg "SLABKERF" 3.0))
                         (list "rot" "Cho xoay vien 90 do (khong giu chieu van)" 'tog (sd:cfg "ST-ROT" t))
                         (list "q" "Do ky khi xep" 'kw (cond (*SD:DTQ*) ("Canbang"))
                               '(("Nhanh" . "Nhanh: 1 cach xep") ("Canbang" . "Can bang: thu nhieu to hop")
                                 ("Ky" . "Ky: them leo doi hoan doi thu tu")))
                         (list "cmp" "So sanh ca 4 kieu mui bac (so tam da can)" 'tog t)
                         (list "ve" "Ve mat cat, so do cat va cac vien (co du lieu SD_TILE cho SDDATHO)" 'tog t)
                         (list "ds" "Ty le ve so do 1/" 'int (cond (*SD:DTSC*) (50))))))
    (exit))
  (setq mat (sd:cfg-put "ST-MAT" (sd:v "mat")) n (sd:cfg-put "ST-N" (sd:v "n"))
        W (sd:cfg-put "ST-W" (sd:v "W")) gd (sd:cfg-put "ST-T" (sd:v "gd")) R (sd:cfg-put "ST-R" (sd:v "R"))
        tm (sd:cfg-put "ST-TM" (sd:v "tm")) tc (sd:cfg-put "ST-TC" (sd:v "tc"))
        kieu (sd:cfg-put "ST-KIEU" (sd:v "kieu")) nho (sd:cfg-put "ST-NHO" (cond ((sd:v "nho")) (0.0)))
        rm (sd:cfg-put "ST-RM" (cond ((sd:v "rm")) (50.0)))
        led (sd:cfg-put "ST-LED" (sd:v "led")) ledv (sd:cfg-put "ST-LEDV" (sd:v "ledv"))
        ledr (sd:cfg-put "ST-LEDR" (cond ((sd:v "ledr")) (17.0))) leds (sd:cfg-put "ST-LEDS" (cond ((sd:v "leds")) (20.0)))
        ledc (sd:cfg-put "ST-LEDC" (cond ((sd:v "ledc")) (20.0)))
        nside (sd:cfg-put "ST-NSIDE" (sd:v "nside")) hl (sd:cfg-put "ST-HL" (sd:v "hl"))
        Lmax (sd:cfg-put "ST-LMAX" (sd:v "Lmax")) gap (sd:cfg-put "ST-GAP" (sd:v "gap"))
        SL (sd:cfg-put "SLABL" (sd:v "SL")) SB (sd:cfg-put "SLABB" (sd:v "SB"))
        trim (sd:cfg-put "SLABTRIM" (sd:v "trim")) kerf (sd:cfg-put "SLABKERF" (sd:v "kerf"))
        Htot (sd:cfg-put "ST-H" (sd:v "Htot")) nve (sd:cfg-put "ST-NVE" (sd:v "nve"))
        dang (sd:cfg-put "ST-DANG" (cond ((sd:v "dang")) ("L")))
        cnl (sd:cfg-put "ST-CNL" (sd:v "cnl")) cnw (sd:cfg-put "ST-CNW" (sd:v "cnw"))
        nq (sd:cfg-put "ST-NQ" (sd:v "nq")) gq (sd:cfg-put "ST-GQ" (sd:v "gq"))
        ri (sd:cfg-put "ST-RI" (sd:v "ri")) ro (sd:cfg-put "ST-RO" (sd:v "ro"))
        dq (sd:cfg-put "ST-DQ" (cond ((sd:v "dq")) ("Thang")))
        rc (sd:cfg-put "ST-RC" (cond ((sd:v "rc")) (1200.0))) dk (sd:cfg-put "ST-DK" (cond ((sd:v "dk")) (250.0)))
        rot (sd:cfg-put "ST-ROT" (sd:v "rot")) q (sd:v "q") *SD:DTQ* q
        ds (float (sd:v "ds")) *SD:DTSC* (fix ds)
        q (cond ((= q "Nhanh") 0) ((= q "Ky") 2) (t 1)))
  ;; tong chieu cao -> chia bac: so bac thang + bac quat, chieu cao bac deu
  (if (> Htot 0.0)
    (progn
      (setq nst (max 1 (fix (+ 0.5 (/ Htot R)))) R (/ Htot nst)
            n (max 1 (fix (+ 0.999999 (/ (float (max 1 (- nst nq))) nve)))))
      (princ (strcat "\n[SD] Tong cao " (sd:num Htot) " mm chia " (itoa nst) " bac (gom " (itoa nq) " bac quat): cao bac "
                     (sd:rtos R 1) " mm, " (itoa nve) " ve x " (itoa n) " bac thang"))))
  ;; cong thuc buoc do: 2R + T trong khoang 600 - 640 mm
  (setq cmf (+ (* 2.0 R) gd))
  (if (or (< cmf 600.0) (> cmf 640.0))
    (princ (strcat "\n [!] 2R + T = " (sd:rtos cmf 0) " mm ngoai khoang 600 - 640 mm di thoai mai; buoc dap goi y " (sd:rtos (- 630.0 (* 2.0 R)) 0) " mm."))
    (princ (strcat "\n 2R + T = " (sd:rtos cmf 0) " mm: dat (600 - 640 mm).")))
  (if (> R 190.0) (princ (strcat "\n [!] Chieu cao bac " (sd:rtos R 1) " mm lon hon 190 mm, kiem tra quy chuan.")))
  (cond
    ((>= led (- R tm)) (princ "\n[SD] Khe LED lon hon chieu cao co bac, kiem tra lai so lieu."))
    ((and (= ledv "Hoc") (>= leds tm)) (princ (strcat "\n[SD] Hoc LED sau " (sd:num leds) " mm >= day mat bac " (sd:num tm) " mm: se xuyen thung mat bac, giam do sau hoac tang day mat bac.")))
    ((and (= ledv "Hoc") (> (+ ledc ledr) (+ gd nho))) (princ "\n[SD] Hoc LED vuot ra ngoai chieu sau mat bac, giam khoang cach tu mep hoac be rong hoc."))
    ((<= (- (+ gd nho) (if (= kieu "Roi") rm 0.0) (if (and (> led 0.0) (= ledv "Matbac")) led 0.0)) 0.0)
     (princ "\n[SD] Mat bac co chieu sau <= 0, kiem tra mui nho / dai mui roi / khe LED."))
    (t
     (setq pcs (sd:st-all kieu n W gd R tm tc nho rm led ledv Lmax gap nside hl nve cnl cnw nq gq ri ro dq rc dk)
           nest (sd:st-nest pcs SL SB trim kerf rot q)
           sm (sd:st-sum nest) tot (sd:st-tot pcs))
     (princ (strcat "\n=== CAU THANG DA " mat ": " (itoa n) " bac, be rong " (sd:num W) ", buoc dap " (sd:num gd)
                    ", cao " (sd:num R) ", mui " (sd:st-name kieu)
                    (if (> led 0.0) (strcat ", khe LED " (sd:num led) " (" ledv ")") "") " ==="))
     (princ "\n Ma  Ten               Dai x Rong (mm)     So luong  Day  Goc cat  Ghi chu")
     (foreach p pcs
       (princ (strcat "\n " (car p) "  " (cadr p) "   " (sd:rtos (nth 2 p) 1) " x " (sd:rtos (nth 3 p) 1)
                      "   x " (itoa (fix (+ 0.5 (nth 4 p)))) "   " (sd:num (nth 5 p)) "   " (sd:rtos (nth 6 p) 1) "   " (nth 7 p))))
     (if (and (= kieu "V45") (not (equal tm tc 0.01)))
       (princ "\n [!] Mat bac va co bac khac do day: ghep vat 45 do se bi lech nac, nen dung cung do day."))
     (princ (strcat "\n Phoi tong " (sd:rtos (car tot) 2) " m2 (thanh pham " (sd:rtos (cadddr tot) 2) " m2); vat 45 do " (sd:rtos (cadr tot) 1) " m; CNC / ranh "
                    (sd:rtos (caddr tot) 1) " m"))
     (princ (strcat "\n Ra da: " (itoa (car sm)) " tam " (sd:num SL) "x" (sd:num SB) " (" (sd:rtos (/ (cadr sm) 1e6) 2) " m2 tho), "
                    "hieu suat " (sd:rtos (if (> (cadr sm) 0) (/ (* 100.0 (caddr sm)) (cadr sm)) 0.0) 1) "%"
                    (if (> (cadddr sm) 0) (strcat ", CHUA XEP " (itoa (cadddr sm)) " vien (qua kho tam)") "")))
     ;; so sanh cac kieu mui bac
     (if (sd:v "cmp")
       (progn
         (princ "\n So sanh phuong an (cung so lieu):")
         (foreach kk '("Thang" "V45" "Roi" "CNC")
           (setq pc (sd:st-all kk n W gd R tm tc nho rm led ledv Lmax gap nside hl nve cnl cnw nq gq ri ro dq rc dk)
                 pn (sd:st-nest pc SL SB trim kerf rot q)
                 sm2 (sd:st-sum pn) tt (sd:st-tot pc))
           (princ (strcat "\n  " (if (= kk kieu) "> " "  ") (sd:st-name kk) ": " (itoa (car sm2)) " tam, hieu suat "
                          (sd:rtos (if (> (cadr sm2) 0) (/ (* 100.0 (caddr sm2)) (cadr sm2)) 0.0) 1) "%, vat 45 "
                          (sd:rtos (cadr tt) 1) " m, CNC " (sd:rtos (caddr tt) 1) " m"
                          (if (> (cadddr sm2) 0) " - CHUA XEP DU" ""))))))
     ;; ve
     (if (and (sd:v "ve") (setq pt (sd:getpt "\nDiem chen ban ve cau thang da (goc trai tren): " nil)))
       (progn
         (setq x0 (car pt) y0 (cadr pt))
         (sd:text (list x0 y0) (strcat "C\\U+1EA6U THANG \\U+0110\\U+00C1 " mat " - " (itoa n) " B\\U+1EACC - M\\U+0168I " (strcase (sd:st-name kieu))) (* 3.5 ds) "L" "SD-CHU")
         (setq y0 (- y0 (* 6 ds)))
         ;; mat bang thang: ve, chieu nghi, bac quat
         (setq plan (sd:st-plan n gd W nve dang cnl cnw nq gq ri ro) bb (sd:st-pbb plan))
         (sd:st-pdraw plan (- x0 (car (car bb))) (- y0 (cadr (cadr bb))) ds)
         (sd:text (list x0 (- y0 (- (cadr (cadr bb)) (cadr (car bb))) (* 4 ds)))
                  (strcat "M\\U+1EB6T B\\U+1EB0NG THANG: " (itoa nve) " v\\U+1EBF \\U+00D7 " (itoa n) " b\\U+1EADc" (if (> nq 0) (strcat ", " (itoa nq) " b\\U+1EADc qu\\U+1EA1t") ""))
                  (* 2.5 ds) "L" "SD-CHU")
         (setq y0 (- y0 (- (cadr (cadr bb)) (cadr (car bb))) (* 14 ds)))
         ;; mat cat 3 bac
         (sd:st-profile (list x0 (- y0 (* 3.0 R)) 0.0) kieu gd R tm tc nho rm led ledv ledr leds ledc)
         (sd:text (list x0 (- y0 (* 3.0 R) (* 4 ds)))
                  (strcat "M\\U+1EB6T C\\U+1EAET 3 B\\U+1EACC: m\\U+1EB7t b\\U+1EADc d\\U+00E0y " (sd:num tm) ", c\\U+1ED5 b\\U+1EADc d\\U+00E0y " (sd:num tc)
                          (if (> led 0.0) (strcat ", khe LED " (sd:num led)) ""))
                  (* 2.5 ds) "L" "SD-CHU")
         (setq y0 (- y0 (* 3.0 R) (* 14 ds)))
         ;; danh sach cac vien co du lieu SD_TILE (dung duoc SDGACHTK, SDDATHO voi kho / tam du, SDGIACONG)
         (setq x0 (car pt) rowh 0.0 col 0)
         (foreach p pcs
           (repeat (fix (+ 0.5 (nth 4 p)))
             (if (> (+ (- x0 (car pt)) (nth 2 p)) 12000.0)
               (setq x0 (car pt) y0 (- y0 rowh (* 4 ds)) rowh 0.0))
             (sd:rect (list x0 (- y0 (nth 3 p)) 0.0) (nth 2 p) (nth 3 p) "SD-GACH-CAT")
             (sd:put-xd (entlast) (sd:tile-xd mat "C" (strcat mat "-" (car p)) (nth 2 p) (nth 3 p)
                                              (* (nth 2 p) (nth 3 p)) 0 mat (nth 2 p) (nth 3 p) 0.0 (nth 5 p) "R"))
             (sd:text (list (+ x0 (/ (nth 2 p) 2.0)) (- y0 (/ (nth 3 p) 2.0))) (car p) (min (* 2.0 ds) (* 0.4 (nth 3 p))) "MC" "SD-CHU")
             (setq x0 (+ x0 (nth 2 p) (* 2 ds)) rowh (max rowh (nth 3 p)))))
         (setq y0 (- y0 rowh (* 14 ds)))
         ;; so do cat da tho
         (foreach g nest
           (setq lays nil)
           (foreach s (cadr g)
             (setq key (vl-princ-to-string (cons (caddr s) (cadr s))))
             (if (setq l (assoc key lays))
               (setq lays (subst (list key (1+ (cadr l)) (caddr l)) l lays))
               (setq lays (cons (list key 1 s) lays))))
           (setq lays (reverse lays))
           (sd:text (list (car pt) y0)
                    (strcat "S\\U+01A0 \\U+0110\\U+1ED2 C\\U+1EAET \\U+0110\\U+00C1 TH\\U+00D4 d\\U+00E0y " (sd:num (car g)) ": " (itoa (length (cadr g))) " t\\U+1EA5m")
                    (* 3.5 ds) "L" "SD-CHU")
           (setq y0 (- y0 (* 12 ds)) x0 (car pt) rowh 0.0 idx 0 maxw 14000.0)
           (foreach l lays
             (setq tp (assoc (caddr (caddr l)) (caddr g)) idx (1+ idx)
                   used (apply '+ (mapcar '(lambda (p) (* (nth 3 p) (nth 4 p))) (cadr (caddr l)))))
             (if (and (> x0 (car pt)) (> (+ (- x0 (car pt)) (nth 4 tp)) maxw))
               (setq x0 (car pt) y0 (- y0 rowh (* 12 ds)) rowh 0.0))
             (setq bx x0 base (- y0 (nth 5 tp)) rowh (max rowh (nth 5 tp)))
             (sd:rect (list bx base 0.0) (nth 4 tp) (nth 5 tp) "SD-GIACONG")
             (sd:rect (list (+ bx trim) (+ base trim) 0.0) (- (nth 4 tp) trim trim) (- (nth 5 tp) trim trim) "SD-KHUAT")
             (foreach p (cadr (caddr l))
               (sd:rect (list (+ bx trim (nth 1 p)) (+ base trim (nth 2 p)) 0.0) (nth 3 p) (nth 4 p) "SD-GACH-CAT")
               (sd:text (list (+ bx trim (nth 1 p) (/ (nth 3 p) 2)) (+ base trim (nth 2 p) (/ (nth 4 p) 2)))
                        (strcat (car p) " " (sd:rtos (nth 3 p) 0) "\\U+00D7" (sd:rtos (nth 4 p) 0))
                        (max (* 0.6 ds) (min (* 2.0 ds) (* 0.25 (min (nth 3 p) (nth 4 p))))) "MC" "SD-CHU")
               (setq lines (cons (sd:join (list mat (sd:num (car g)) (itoa idx) (itoa (cadr l)) (car p)
                                                (sd:rtos (nth 1 p) 0) (sd:rtos (nth 2 p) 0)
                                                (sd:rtos (nth 3 p) 0) (sd:rtos (nth 4 p) 0)
                                                (if (= (nth 5 p) 1) "Co" "Khong")) ";")
                                 lines)))
             (sd:text (list bx (+ y0 (* 2 ds)))
                      (strcat "T\\U+1EA4M " (itoa idx) " (\\U+00D7" (itoa (cadr l)) ") s\\U+1EED d\\U+1EE5ng "
                              (sd:rtos (/ (* 100.0 used) (* (nth 4 tp) (nth 5 tp))) 1) "%")
                      (* 2.5 ds) "L" "SD-CHU")
             (setq x0 (+ x0 (nth 4 tp) (* 0.15 (nth 4 tp)))))
           (setq y0 (- y0 rowh (* 20 ds))))))
     ;; CSV: bang vien va so do cat
     (setq fn (sd:csv-name "_CauThangDa.csv"))
     (if (setq f (sd:open fn "w"))
       (progn
         (write-line "sep=;" f)
         (write-line "Ma;Ten;Dai (mm);Rong (mm);So luong;Day (mm);Goc cat (do);Vat 45 moi vien (mm);CNC moi vien (mm);Ghi chu" f)
         (foreach p pcs
           (write-line (sd:join (list (car p) (cadr p) (sd:rtos (nth 2 p) 1) (sd:rtos (nth 3 p) 1) (itoa (fix (+ 0.5 (nth 4 p))))
                                      (sd:num (nth 5 p)) (sd:rtos (nth 6 p) 1) (sd:rtos (nth 8 p) 1) (sd:rtos (nth 9 p) 1) (nth 7 p)) ";")
                       f))
         (write-line "" f)
         (write-line "Ma VL;Day tam;Tam so;So tam giong;Ma vien;x (mm);y (mm);Rong (mm);Cao (mm);Xoay" f)
         (foreach l (reverse lines) (write-line l f))
         (setq fn (sd:close f))
         (princ (strcat "\n[SD] Da xuat: " fn))))))
  (sd:finish))
(defun sd:pairs (l / r) (while (cadr l) (setq r (cons (list (car l) (cadr l)) r) l (cddr l))) (reverse r))

;;; --------------------------------------------------------------------------
;;;  Cat duong thang voi o san co lo: khoang [d0 d1] theo khoang cach tu p1
;;; --------------------------------------------------------------------------
(defun sd:clip-iv (p1 p2 poly / ip a r q)
  (setq a (last poly))
  (foreach b poly
    (if (setq ip (inters p1 p2 a b t)) (setq r (cons (distance p1 ip) r)))
    (setq a b))
  (foreach x (vl-sort r '<) (if (not (and q (equal x (car q) 1e-6))) (setq q (cons x q))))
  (sd:pairs (reverse q)))

(defun sd:iv-minus (ivs cut / r a b)
  (foreach iv ivs
    (setq a (car iv) b (cadr iv))
    (foreach c (sd:sort cut '(lambda (x y) (< (car x) (car y))))
      (if (and (< (car c) b) (> (cadr c) a))
        (progn (if (> (car c) a) (setq r (cons (list a (car c)) r)))
               (setq a (max a (cadr c))))))
    (if (> b a) (setq r (cons (list a b) r))))
  (reverse r))

;; Cac doan cua p1-p2 nam trong o san (outer tru holes)
(defun sd:clip-segh (p1 p2 outer holes / u ivs)
  (setq u (angle p1 p2) p1 (sd:2d (polar p1 (+ u pi) 10.0)) p2 (sd:2d (polar p2 u 10.0))
        ivs (sd:clip-iv p1 p2 outer))
  (foreach h holes (setq ivs (sd:iv-minus ivs (sd:clip-iv p1 p2 h))))
  (mapcar '(lambda (iv) (list (sd:2d (polar p1 u (car iv))) (sd:2d (polar p1 u (cadr iv))))) ivs))

;; ---- SDLIENKET -----------------------------------------------------------------
;; Bo ma dinh dang MTEXT -> chu thuong
(defun sd:mt-plain (s / r i c n)
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (setq n (substr s (1+ i) 1))
       (cond ((member n '("P" "~")) (setq r (strcat r " ") i (+ i 2)))
             ((member n '("\\" "{" "}")) (setq r (strcat r n) i (+ i 2)))
             ((member (strcase n) '("F" "H" "C" "W" "Q" "T" "A" "P" "S"))
              (setq i (1+ i))
              (while (and (<= i (strlen s)) (/= (substr s i 1) ";")) (setq i (1+ i)))
              (setq i (1+ i)))
             (t (setq i (+ i 2)))))
      ((member c '("{" "}")) (setq i (1+ i)))
      (t (setq r (strcat r c) i (1+ i)))))
  r)

(defun sd:lk-mark (p r txt sc)
  (entmake (list '(0 . "CIRCLE") '(8 . "SD-KIEMTRA") (cons 10 p) (cons 40 r)))
  (sd:text (sd:p+ p 0 (+ r sc)) txt (* 2.5 sc) "L" "SD-KIEMTRA"))
(defun sd:al-sortd (l) (mapcar '(lambda (k) (nth k l)) (vl-sort-i l '>)))

;; Bang ma tam
(defun sd:al-add (bom code n / o)
  (if (setq o (assoc code bom)) (subst (cons code (+ (cdr o) n)) o bom) (cons (cons code n) bom)))
(defun sd:al-sorted (bom) (mapcar '(lambda (k) (nth k bom)) (vl-sort-i (mapcar 'car bom) 'sd:fl<)))
(defun sd:col-last (c) (entmod (append (entget (entlast)) (list (cons 62 c)))))

;;; --------------------------------------------------------------------------
;;;  SDRAITAM - Rai panel / da lat theo kho (Tiling Algorithm)
;;;    Che do Panel: tam tieu chuan (lon nhat) rai tu goc X, Y nho nhat cua tung o; phan thieu (mep bien) chia
;;;                  bang tam di hinh trong kho (it tam nhat, tam lon truoc), con thua = go (layer INFILL-TIMBER)
;;;    Che do Da    : vien lat nguyen + vien cat o mep, danh so theo thu tu lat, huong van da (tiep noi /
;;;                  doi guong / xoay 4 chieu); vien mang du lieu SD_TILE nen SDGACHTK / SDDATHO / SDGIACONG dung duoc
;;; --------------------------------------------------------------------------
(defun sd:gcd (a b / r) (while (> b 0) (setq r (rem a b) a b b r)) a)

;; "600x1200:10, 400x1200" -> ((600.0 1200.0 10) (400.0 1200.0 0)); so luong 0 / bo trong = khong han che
(defun sd:rt-parse (s / r x d q)
  (foreach it (sd:split (strcase s) ",")
    (setq x (sd:split it ":") q (if (cadr x) (atoi (cadr x)) 0)
          d (sd:split (vl-string-translate "*" "X" (car x)) "X"))
    (if (and (cadr d) (> (atof (car d)) 0.0) (> (atof (cadr d)) 0.0))
      (setq r (cons (list (atof (car d)) (atof (cadr d)) q) r))))
  (reverse r))

(defun sd:rt-code (a b) (strcat "P" (sd:num (min a b)) "x" (sd:num (max a b))))

;; Kho -> moi tam co ca 2 chieu quay (trung kich thuoc thi giu mot)
(defun sd:rt-orient (stk / r)
  (foreach s stk
    (if (not (vl-some '(lambda (x) (and (equal (car x) (car s) 0.5) (equal (cadr x) (cadr s) 0.5))) r))
      (setq r (cons s r)))
    (if (and (> (abs (- (car s) (cadr s))) 0.5)
             (not (vl-some '(lambda (x) (and (equal (car x) (cadr s) 0.5) (equal (cadr x) (car s) 0.5))) r)))
      (setq r (cons (list (cadr s) (car s) (caddr s)) r))))
  (reverse r))

(defun sd:rt-used (used code) (cond ((cdr (assoc code used))) (0)))
(defun sd:rt-bump (used code / o)
  (if (setq o (assoc code used)) (subst (cons code (1+ (cdr o))) o used) (cons (cons code 1) used)))
;; So tam con lai cua kho s (khong han che = 1e9)
(defun sd:rt-left (s used)
  (if (<= (caddr s) 0) 1e9 (- (caddr s) (sd:rt-used used (sd:rt-code (car s) (cadr s))))))

;; Chia doan L (mm) bang cac be rong ws: it tam nhat, uu tien tam lon, phan du la go -> (tam... phan-du)
(defun sd:rt-fill1 (L ws / u n wu rb i best c k w pcs cov lf)
  (setq ws (vl-sort (mapcar '(lambda (x) (fix (+ x 0.5))) ws) '>) u 0)
  (foreach w ws (setq u (sd:gcd (max u w) (min u w))))
  (cond
    ((or (null ws) (< u 1)) (list nil L))
    ((> (fix (/ (+ L 1e-6) u)) 1500)
     (setq lf L)
     (foreach w ws (while (<= w (+ lf 1e-6)) (setq pcs (cons (float w) pcs) lf (- lf w))))
     (list (sd:al-sortd pcs) lf))
    (t
     (setq n (fix (/ (+ L 1e-6) u)) wu (mapcar '(lambda (x) (/ x u)) ws) rb (list (cons 0 nil)) i 0)
     (repeat n
       (setq i (1+ i) best nil)
       (foreach w wu
         (if (and (<= w i) (setq c (nth (1- w) rb)) (or (null best) (< (1+ (car c)) (car best))))
           (setq best (cons (1+ (car c)) w))))
       (setq rb (cons best rb)))
     (setq k 0)
     (while (and (< k n) (null (nth k rb))) (setq k (1+ k)))
     (setq i (- n k) cov (* i u))
     (while (> i 0)
       (setq c (nth (- n i) rb) w (cdr c) pcs (cons (float (* w u)) pcs) i (- i w)))
     (list (sd:al-sortd pcs) (- L cov)))))

(defun sd:rt-shift (lst dx dy) (mapcar '(lambda (r) (list (+ (car r) dx) (+ (cadr r) dy) (caddr r) (cadddr r))) lst))
(defun sd:rt-swap (r) (list (cadr r) (car r) (cadddr r) (caddr r)))
(defun sd:rt-tarea (r) (apply '+ (cons 0.0 (mapcar '(lambda (x) (* (caddr x) (cadddr x))) (cadr r)))))

;; Lap day o chu nhat w x h (goc trai duoi = 0,0) theo hang: hang cao nhat vua o, chia be rong bang tam cung chieu cao,
;; phan du be rong / chieu cao de quy; khong tam nao vua -> go.
;; stk = kho da co ca 2 chieu quay; used = so tam da dung. Tra ve (tam go used) voi tam / go = (x y rong cao)
(defun sd:rt-row (w h stk used / ex cand hh r ok x pan n pw sub rest cnt)
  (cond
    ((or (< w 1.0) (< h 1.0)) (list nil nil used))
    ((setq ex (vl-some '(lambda (s) (if (and (equal (car s) w 1.0) (equal (cadr s) h 1.0) (> (sd:rt-left s used) 0)) s)) stk))
     (list (list (list 0.0 0.0 w h)) nil (sd:rt-bump used (sd:rt-code (car ex) (cadr ex)))))
    (t
     (setq cand (vl-remove-if-not '(lambda (s) (and (<= (cadr s) (+ h 1.0)) (> (sd:rt-left s used) 0))) stk))
     (if (null cand)
       (list nil (list (list 0.0 0.0 w h)) used)
       (progn
         (setq hh (apply 'max (mapcar 'cadr cand))
               cand (vl-remove-if-not '(lambda (s) (equal (cadr s) hh 1.0)) cand)
               ok nil)
         (while (not ok)
           (setq r (sd:rt-fill1 w (mapcar 'car cand)) ok t)
           (foreach s cand
             (setq n (length (vl-remove-if-not '(lambda (v) (equal v (car s) 1.0)) (car r))))
             (if (and ok (> n (sd:rt-left s used)))
               (setq cand (vl-remove s cand) ok nil))))
         (if (null (car r))
           ;; khong tam nao vua be rong: bo nhom chieu cao nay roi thu lai
           (sd:rt-row w h (vl-remove-if '(lambda (s) (equal (cadr s) hh 1.0)) stk) used)
           (progn
             (setq x 0.0)
             (foreach pw (car r)
               (setq pan (cons (list x 0.0 pw hh) pan) x (+ x pw) used (sd:rt-bump used (sd:rt-code pw hh))))
             (setq pan (reverse pan))
             (if (> (- w x) 1.0)
               (progn (setq sub (sd:rt-row (- w x) hh stk used))
                      (setq pan (append pan (sd:rt-shift (car sub) x 0.0)) cnt (sd:rt-shift (cadr sub) x 0.0) used (caddr sub))))
             (setq rest (- h hh))
             (if (> rest 1.0)
               (progn (setq sub (sd:rt-row w rest stk used))
                      (setq pan (append pan (sd:rt-shift (car sub) 0.0 hh)) cnt (append cnt (sd:rt-shift (cadr sub) 0.0 hh)) used (caddr sub))))
             (list pan cnt used))))))))

;; Chon cach lap day (theo hang hoac theo cot) it go nhat
(defun sd:rt-fit (w h stk used / a b)
  (setq a (sd:rt-row w h stk used)
        b (sd:rt-row h w (mapcar '(lambda (s) (list (cadr s) (car s) (caddr s))) stk) used)
        b (list (mapcar 'sd:rt-swap (car b)) (mapcar 'sd:rt-swap (cadr b)) (caddr b)))
  (if (or (< (sd:rt-tarea b) (- (sd:rt-tarea a) 1.0))
          (and (<= (abs (- (sd:rt-tarea b) (sd:rt-tarea a))) 1.0) (< (length (car b)) (length (car a)))))
    b a))

;; Huong van da cua vien (i, j): (so-lan-xoay-90 lat-ngang lat-doc)
(defun sd:rt-vein (van i j)
  (cond ((= van "Tiepnoi") (list 0 nil nil))
        ((= van "Doiguong") (list 0 (= (rem i 2) 1) (= (rem j 2) 1)))
        ((= van "Xoay4") (list (+ (* 2 (rem j 2)) (rem i 2)) nil nil))
        ((= van "Ngaunhien") (list (rem (+ (* i 3) (* j 5)) 4) (= (rem (+ i j j) 2) 1) (= (rem (+ i i j) 3) 0)))))

(defun sd:rt-vpts (vd cx cy w h / r p u v t1)
  (foreach p '((0.15 0.15) (0.40 0.52) (0.58 0.44) (0.85 0.85))
    (setq u (car p) v (cadr p))
    (repeat (car vd) (setq t1 (- 1.0 v) v u u t1))
    (if (cadr vd) (setq u (- 1.0 u)))
    (if (caddr vd) (setq v (- 1.0 v)))
    (setq r (cons (list (+ cx (* u w)) (+ cy (* v h))) r)))
  (reverse r))

(defun sd:rt-color (code stk0 / i r1)
  (setq i 0 r1 nil)
  (foreach s stk0 (if (= (sd:rt-code (car s) (cadr s)) code) (setq r1 i)) (setq i (1+ i)))
  (if r1 (nth (rem r1 8) '(3 4 5 6 30 140 200 92)) 1))

;; Cat vien (cs) voi region R: (dien-tich ents toa-do-dinh). ents tren layer lay; nil neu ngoai vung
(defun sd:rt-clip (rg cs lay / e tr cp pa ents vp)
  (sd:pline cs t lay)
  (setq e (entlast) tr (sd:region e))
  (entdel e)
  (if tr
    (progn
      (setq cp (vla-Copy rg))
      (vla-Boolean cp 1 tr)
      (setq pa (vla-get-Area cp))
      (if (< pa 1.0)
        (progn (vla-Delete cp) nil)
        (progn
          (setq ents (sd:region->ents cp lay))
          (foreach x ents
            (if (= (cdr (assoc 0 (entget x))) "LWPOLYLINE")
              (foreach g (entget x) (if (= (car g) 10) (setq vp (cons (sd:2d (cdr g)) vp))))))
          (list pa ents (reverse vp)))))))

(defun sd:rt-poly-of (e / pts) (setq pts (sd:curve-pts e)) (list e pts (abs (sd:area pts))))

;; Mau van da khuyen nghi theo file .pat: (ten ti-le mau nen). mau = so ACI hoac (r g b); nen = ACI hoac nil
(setq *SD:VANDA*
  '(("Platinus" 1.2 253 252) ("DaSocDua" 0.4 (88 103 115) nil) ("ViaLactea" 1.5 7 250)
    ("DaVanGoXam" 0.75 8 nil) ("DaVanGoCo" 1.5 32 nil)))
(defun sd:vp-pre (nm) (cond ((assoc nm *SD:VANDA*)) (t (list nm 1.0 7 nil))))

(defun sd:vp-color (h col / tc)
  (if (listp col)
    (progn (setq tc (vla-get-TrueColor h)) (vla-SetRGB tc (car col) (cadr col) (caddr col)) (vla-put-TrueColor h tc))
    (vla-put-Color h col)))

;; Hatch van da (nen + van tu file .pat) tren cac bien ents. Tra ve nil neu khong tao duoc (thieu file .pat)
(defun sd:vp-hatch (ents nm sc ang org col bg / ms h r)
  (setq ms (sd:ms))
  (if bg
    (vl-catch-all-apply
      '(lambda ()
         (setq h (vla-AddHatch ms 1 "SOLID" :vlax-true))
         (vla-AppendOuterLoop h (sd:objarr (mapcar 'vlax-ename->vla-object ents)))
         (vla-put-Color h bg) (vla-put-Layer h "SD-GACH-VAN") (vla-Evaluate h))
      nil))
  (setq h nil
        r (vl-catch-all-apply
            '(lambda ()
               (setq h (vla-AddHatch ms 2 nm :vlax-true))
               (vla-AppendOuterLoop h (sd:objarr (mapcar 'vlax-ename->vla-object ents)))
               (vla-put-PatternScale h sc)
               (vla-put-PatternAngle h (* pi (/ ang 180.0)))
               (vla-put-Origin h (vlax-make-variant (vlax-safearray-fill (vlax-make-safearray vlax-vbDouble '(0 . 1)) (list (float (car org)) (float (cadr org))))))
               (vla-put-Layer h "SD-GACH-VAN")
               (sd:vp-color h col)
               (vla-Evaluate h))
            nil))
  (if (vl-catch-all-error-p r)
    (progn
      (if h (vl-catch-all-apply 'vla-Delete (list h)))
      (if (not *SD:VPWARN*)
        (progn (setq *SD:VPWARN* t)
               (princ (strcat "\n[SD] Khong tao duoc hatch '" nm "': " (vl-catch-all-error-message r)
                              "\n     Chep file " nm ".pat vao thu muc dist (da co trong Support Path sau SDMENU) roi chay lai.")))
        nil)
      nil)
    t))

;; Goc xoay hatch xap xi theo huong van (hatch khong lat guong duoc)
(defun sd:rt-vang (vd)
  (if vd (+ (* 90 (car vd)) (if (and (cadr vd) (caddr vd)) 180 (if (or (cadr vd) (caddr vd)) 90 0))) 0))

;; Hatch 1 vien: Tiepnoi / khong ve van -> goc luoi chung (van chay lien tuc qua cac vien); kieu khac -> goc tung vien
(defun sd:rt-vh (ents nm sc van vd cx cy ox oy / pre)
  (setq pre (sd:vp-pre nm))
  (foreach e ents
    (if (= (cdr (assoc 0 (entget e))) "LWPOLYLINE")
      (sd:vp-hatch (list e) nm sc (+ (sd:rt-vang vd) (cond (*SD:RTAOFF*) (0.0))) (if (member van '("Tiepnoi" "Khong")) (list ox oy) (list cx cy)) (nth 2 pre) (nth 3 pre)))))

(defun c:SDVANDA (/ ss i e pts bb xs ys flt vph vps van vpc vd ii jj ox oy n)
  (sd:begin)
  (setq *SD:RTAOFF* 0.0)
  (if (not (sd:dlg "Hatch van da len vien (SDVANDA)"
                   (list (list "vp" "Pattern van da" 'kw (cond (*SD:VPH*) ("Platinus"))
                               '(("Platinus" . "Platinus - nen xam sang, van toi") ("DaSocDua" . "Da Soc Dua 300x600") ("ViaLactea" . "Via Lactea - nen den")
                                 ("DaVanGoXam" . "Da Van Go Xam") ("DaVanGoCo" . "Da Van Go Co") ("Khac" . "Ten pattern khac (nhap ben duoi)")))
                         (list "vpn" "Ten pattern khac (file .pat trong Support Path)" 'str "" nil '("vp" "Khac"))
                         (list "vsc" "Ti le hatch (0 = khuyen nghi theo pattern)" 'real0 0.0)
                         (list "van" "Huong van" 'kw (cond (*SD:RTVAN*) ("Tiepnoi"))
                               '(("Tiepnoi" . "Tiep noi (van chay lien tuc)") ("Doiguong" . "Doi guong") ("Xoay4" . "Xoay 4 chieu") ("Ngaunhien" . "Ngau nhien"))))))
    (exit))
  (setq vph (sd:v "vp") van (sd:v "van") *SD:VPH* vph *SD:RTVAN* van)
  (if (= vph "Khac") (setq vph (sd:v "vpn")))
  (setq vpc (sd:vp-pre vph) vps (if (> (sd:v "vsc") 0.0) (sd:v "vsc") (cadr vpc))
        flt '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT") (-4 . "&") (70 . 1)))
  (princ "\nChon cac vien can hatch van <Enter = tat ca vien SD-GACH / SD-GACH-CAT>: ")
  (setq ss (ssget flt))
  (if (null ss) (setq ss (ssget "_X" flt)))
  (if (null ss)
    (princ "\n[SD] Khong co vien nao (layer SD-GACH / SD-GACH-CAT).")
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) bb (sd:bbox (sd:curve-pts e)))
        (setq pts (cons (list e (caar bb) (cadar bb)) pts)
              xs (cons (fix (+ 0.5 (caar bb))) xs) ys (cons (fix (+ 0.5 (cadar bb))) ys)))
      (setq xs (vl-sort xs '<) ys (vl-sort ys '<) ox (car xs) oy (car ys) n 0)
      (foreach p pts
        (setq ii (vl-position (fix (+ 0.5 (cadr p))) xs) jj (vl-position (fix (+ 0.5 (caddr p))) ys)
              vd (sd:rt-vein van ii jj))
        (if (sd:rt-vh (list (car p)) vph vps van vd (cadr p) (caddr p) (float ox) (float oy)) (setq n (1+ n))))
      (princ (strcat "\n[SD] Da hatch van '" vph "' cho " (itoa n) " / " (itoa (length pts)) " vien (layer SD-GACH-VAN)."))))
  (sd:finish))

;; ---- Xep vien vao tam da tho (shelf packing, cho phep xoay 90 do), nhieu tam ----
;; items = ((id rong cao) ...). Tra ve (placements so-tam); placement = (id tam x y rong cao xoay), tam = nil neu khong vua
(defun sd:lset (lst i v / r k)
  (setq k 0)
  (foreach x lst (setq r (cons (if (= k i) v x) r) k (1+ k)))
  (reverse r))

;; Ban sao tam da tho (anh) dung kich thuoc that SW x SH, goc xoay 0: (doi-tuong goc-x goc-y)
(defun sd:img-master (e SW SH / c o f wd ht)
  (setq c (vla-Copy (vlax-ename->vla-object e)))
  (if (> (abs (vla-get-Rotation c)) 1e-6) (vla-put-Rotation c 0.0))
  (setq o (vlax-get c 'Origin) wd (vla-get-Width c) ht (vla-get-Height c))
  (if (> (abs (- (/ wd ht) (/ SW SH))) (* 0.02 (/ SW SH)))
    (princ (strcat "\n[SD] Ti le anh (" (sd:num wd) " x " (sd:num ht) ") lech ti le tam that (" (sd:num SW) " x " (sd:num SH)
                   "): vien cat se lech neu anh bi cat vien hoac keo gian.")))
  (vla-ScaleEntity c (vlax-3d-point (car o) (cadr o) 0.0) (/ SW wd))
  (list c (car o) (cadr o)))

;; So do cat tam da (ve tai pt): khung tam + vien da xep, so hieu vien
;;; ---- So do cat tam da: vien = to xanh la + so hieu + kich thuoc; vun = to xam + kich thuoc; duong cat = do, balloon so thu tu cat ----
(defun sd:dg-layers ()
  (sd:make-layer "SD-NEST-TAM" 7 "Continuous" 50)
  (sd:make-layer "SD-NEST-LE" 8 "DASHED" 13)
  (sd:make-layer "SD-NEST-VIEN" 3 "Continuous" 35)
  (sd:make-layer "SD-NEST-VUN" 9 "Continuous" 13)
  (sd:make-layer "SD-NEST-TO" 9 "Continuous" 13)
  (sd:make-layer "SD-DUONG-CAT" 1 "Continuous" 25)
  (sd:make-layer "SD-NEST-CHU" 7 "Continuous" 18))

;; To mau dac hinh chu nhat (hatch SOLID, trong suot ~70%): thu nhieu cach ghi de chay duoc tren moi ban AutoCAD
(defun sd:dg-fill (x y w h col lay / base tail pts)
  (setq pts (list (list 10 x y) (list 10 (+ x w) y) (list 10 (+ x w) (+ y h)) (list 10 x (+ y h)))
        base (list '(0 . "HATCH") '(100 . "AcDbEntity") (cons 8 lay) (cons 62 col))
        tail (list '(100 . "AcDbHatch") '(10 0.0 0.0 0.0) '(210 0.0 0.0 1.0) '(2 . "SOLID") '(70 . 1) '(71 . 0) '(91 . 1)))
  (or (entmake (append base (list (cons 440 33554508)) tail (list '(92 . 7) '(72 . 0) '(73 . 1) '(93 . 4)) pts (list '(97 . 0) '(75 . 0) '(76 . 1) '(98 . 0))))
      (entmake (append base tail (list '(92 . 7) '(72 . 0) '(73 . 1) '(93 . 4)) pts (list '(97 . 0) '(75 . 0) '(76 . 1) '(98 . 0))))
      (entmake (append base tail (list '(92 . 3) '(72 . 0) '(73 . 1) '(93 . 4)) pts (list '(97 . 0) '(75 . 0) '(76 . 1) '(98 . 0))))))

;; Chu 1 dong co mau + goc xoay (rad)
(defun sd:dg-text (pt str h j lay col ang / h72 v73)
  (setq h72 (cond ((wcmatch j "*C") 1) ((wcmatch j "*R") 2) (t 0))
        v73 (cond ((wcmatch j "M?") 2) ((wcmatch j "T?") 3) (t 0)))
  (entmake (list '(0 . "TEXT") (cons 8 lay) (cons 62 col) (cons 7 (sd:tstyle)) (cons 10 pt)
                 (cons 11 pt) (cons 40 h) (cons 1 str) (cons 50 ang) (cons 72 h72) (cons 73 v73))))

;; Chu 1 dong vua o w x h: ngang, hoac xoay 90 do neu o cao hon rong nhieu; hmax = cao toi da, hmin = nho nhat con doc duoc; tra ve (cao goc) hoac nil
(defun sd:dg-fit (str w h hmax hmin / n hh a)
  (setq n (max 1 (strlen str))
        hh (min hmax (* 0.85 h) (/ (* 0.92 w) (* 0.75 n))))
  (if (>= hh hmin) (setq a (list hh 0.0)))
  (if (> h (* 1.5 w))
    (progn
      (setq hh (min hmax (* 0.85 w) (/ (* 0.92 h) (* 0.75 n))))
      (if (and (>= hh hmin) (or (null a) (> hh (car a)))) (setq a (list hh (/ pi 2.0))))))
  a)

;; Nhan vien trong o: dong 1 = so hieu (to), dong 2 = kich thuoc (nho, neu con cho)
(defun sd:dg-tile-label (id w h cx cy sc / s2 f1 th1 ang aw ah th2 gap d1 d2 ux uy)
  (setq s2 (strcat (sd:rtos w 0) "x" (sd:rtos h 0))
        f1 (sd:dg-fit id w h (* 2.4 sc) (* 0.9 sc)))
  (if f1
    (progn
      (setq th1 (car f1) ang (cadr f1)
            aw (if (= ang 0.0) w h) ah (if (= ang 0.0) h w)
            th2 (min (* 0.62 th1) (/ (* 0.92 aw) (* 0.75 (strlen s2))))
            gap (* 0.35 th1) ux (- (sin ang)) uy (cos ang))
      (if (and (>= th2 (* 0.7 sc)) (>= ah (+ th1 gap (* 1.3 th2))))
        (setq d1 (/ (+ th2 gap) 2.0) d2 (- (/ (+ th1 gap) 2.0))
              d1 (+ d1 0.0))
        (setq d1 0.0 th2 nil))
      (sd:dg-text (list (+ cx (* ux d1)) (+ cy (* uy d1)) 0.0) id th1 "MC" "SD-NEST-CHU" 7 ang)
      (if th2
        (sd:dg-text (list (+ cx (* ux d2)) (+ cy (* uy d2)) 0.0) s2 th2 "MC" "SD-NEST-CHU" 2 ang)))))

;; Ve so do cat cho nsl tam: khung tam (net day) + le xen (net dut) + vien (to xanh) + vun (to xam) + duong cat (do, balloon thu tu)
;; cuts / remn = nil khi chi ve vi tri xep
(defun sd:dg-draw (pls nsl SW SH pt sc cuts remn / k x0 y0 pl q ct n a b r trim used nt nr nc lay1 gx f dx dy)
  (sd:dg-layers)
  (setq trim (cond (*SD:ITRIM*) (0.0)) r (* 1.3 sc) y0 (cadr pt) k 0
        dx (+ SW (max 300.0 (* 8.0 sc))))
  (repeat nsl
    (setq x0 (+ (car pt) (* k dx)) used 0.0 nt 0 nr 0 nc 0)
    ;; 1) to mau nen: vun (xam) roi vien (xanh) - ve truoc de net / chu nam tren
    (foreach q (vl-remove-if-not '(lambda (r2) (= (car r2) k)) remn)
      (setq nr (1+ nr))
      (sd:dg-fill (+ x0 (nth 1 q)) (+ y0 (nth 2 q)) (nth 3 q) (nth 4 q) 9 "SD-NEST-TO"))
    (foreach pl pls
      (if (equal (cadr pl) k)
        (progn (setq nt (1+ nt) used (+ used (* (nth 4 pl) (nth 5 pl))))
               (sd:dg-fill (+ x0 (nth 2 pl)) (+ y0 (nth 3 pl)) (nth 4 pl) (nth 5 pl) 3 "SD-NEST-TO"))))
    ;; 2) khung tam + le xen
    (sd:rect (list x0 y0 0.0) SW SH "SD-NEST-TAM")
    (if (and (> trim 0.5) (< (* 2.0 trim) (min SW SH)))
      (sd:rect (list (+ x0 trim) (+ y0 trim) 0.0) (- SW (* 2.0 trim)) (- SH (* 2.0 trim)) "SD-NEST-LE"))
    ;; 3) net vien va vun
    (foreach q (vl-remove-if-not '(lambda (r2) (= (car r2) k)) remn)
      (sd:rect (list (+ x0 (nth 1 q)) (+ y0 (nth 2 q)) 0.0) (nth 3 q) (nth 4 q) "SD-NEST-VUN"))
    (foreach pl pls
      (if (equal (cadr pl) k)
        (sd:rect (list (+ x0 (nth 2 pl)) (+ y0 (nth 3 pl)) 0.0) (nth 4 pl) (nth 5 pl) "SD-NEST-VIEN")))
    ;; 4) duong cat do + balloon thu tu o dau net (khong de len giua net cho khoi che chu)
    (setq n 0)
    (foreach ct (sd:cut-seq (vl-remove-if-not '(lambda (c) (= (car c) k)) cuts))
      (setq n (1+ n) nc n
            a (list (+ x0 (nth 1 ct)) (+ y0 (nth 2 ct)) 0.0)
            b (list (+ x0 (nth 3 ct)) (+ y0 (nth 4 ct)) 0.0))
      (sd:line a b "SD-DUONG-CAT")
      (sd:circle a r "SD-DUONG-CAT")
      (sd:dg-text a (itoa n) (* 1.25 sc) "MC" "SD-DUONG-CAT" 1 0.0))
    ;; 5) chu: so hieu + kich thuoc vien, kich thuoc vun (chi ghi khi vua o)
    (foreach pl pls
      (if (equal (cadr pl) k)
        (sd:dg-tile-label (car pl) (nth 4 pl) (nth 5 pl)
                          (+ x0 (nth 2 pl) (/ (nth 4 pl) 2.0)) (+ y0 (nth 3 pl) (/ (nth 5 pl) 2.0)) sc)))
    (foreach q (vl-remove-if-not '(lambda (r2) (= (car r2) k)) remn)
      (if (setq f (sd:dg-fit (strcat "VUN " (sd:rtos (nth 3 q) 0) "x" (sd:rtos (nth 4 q) 0)) (nth 3 q) (nth 4 q) (* 1.5 sc) (* 0.8 sc)))
        (sd:dg-text (list (+ x0 (nth 1 q) (/ (nth 3 q) 2.0)) (+ y0 (nth 2 q) (/ (nth 4 q) 2.0)) 0.0)
                    (strcat "VUN " (sd:rtos (nth 3 q) 0) "x" (sd:rtos (nth 4 q) 0)) (car f) "MC" "SD-NEST-CHU" 7 (cadr f))))
    ;; 6) tieu de + tom tat
    (sd:dg-text (list (+ x0 (/ SW 2.0)) (+ y0 SH (* 5.5 sc)) 0.0) (strcat "TAM DA " (itoa (1+ k))) (* 3.0 sc) "MC" "SD-NEST-CHU" 7 0.0)
    (sd:dg-text (list (+ x0 (/ SW 2.0)) (+ y0 SH (* 2.2 sc)) 0.0)
                (strcat (sd:rtos SW 0) " x " (sd:rtos SH 0) " mm  |  " (itoa nt) " vien  |  dung " (sd:rtos (* 100.0 (/ used (* SW SH))) 1) " %"
                        (if cuts (strcat "  |  " (itoa nc) " duong cat") "")
                        (if remn (strcat "  |  " (itoa nr) " vun") ""))
                (* 1.7 sc) "MC" "SD-NEST-CHU" 7 0.0)
    (setq k (1+ k)))
  ;; chu giai (1 lan, duoi tam dau)
  (setq gx (car pt) y0 (- (cadr pt) (* 4.0 sc)))
  (sd:dg-fill gx (- y0 (* 2.0 sc)) (* 3.0 sc) (* 2.0 sc) 3 "SD-NEST-TO")
  (sd:rect (list gx (- y0 (* 2.0 sc)) 0.0) (* 3.0 sc) (* 2.0 sc) "SD-NEST-VIEN")
  (sd:dg-text (list (+ gx (* 4.0 sc)) (- y0 sc) 0.0) "VIEN CAT (so hieu T.. + kich thuoc dai x rong)" (* 1.5 sc) "ML" "SD-NEST-CHU" 7 0.0)
  (if remn
    (progn
      (setq y0 (- y0 (* 3.2 sc)))
      (sd:dg-fill gx (- y0 (* 2.0 sc)) (* 3.0 sc) (* 2.0 sc) 9 "SD-NEST-TO")
      (sd:rect (list gx (- y0 (* 2.0 sc)) 0.0) (* 3.0 sc) (* 2.0 sc) "SD-NEST-VUN")
      (sd:dg-text (list (+ gx (* 4.0 sc)) (- y0 sc) 0.0) "VUN / PHE LIEU GIU LAI (khong dung lam vien)" (* 1.5 sc) "ML" "SD-NEST-CHU" 7 0.0)))
  (if cuts
    (progn
      (setq y0 (- y0 (* 3.2 sc)))
      (sd:line (list gx (- y0 sc) 0.0) (list (+ gx (* 3.0 sc)) (- y0 sc) 0.0) "SD-DUONG-CAT")
      (sd:circle (list gx (- y0 sc) 0.0) r "SD-DUONG-CAT")
      (sd:dg-text (list gx (- y0 sc) 0.0) "1" (* 1.25 sc) "MC" "SD-DUONG-CAT" 1 0.0)
      (sd:dg-text (list (+ gx (* 4.0 sc)) (- y0 sc) 0.0) "DUONG CAT: so trong balloon = thu tu cat (cat tach lon truoc, manh nho sau cung)" (* 1.5 sc) "ML" "SD-NEST-CHU" 1 0.0)))
  (if (> trim 0.5)
    (progn
      (setq y0 (- y0 (* 3.2 sc)))
      (sd:line (list gx (- y0 sc) 0.0) (list (+ gx (* 3.0 sc)) (- y0 sc) 0.0) "SD-NEST-LE")
      (sd:dg-text (list (+ gx (* 4.0 sc)) (- y0 sc) 0.0) (strcat "LE XEN BIEN " (sd:rtos trim 0) " mm (khong dung)") (* 1.5 sc) "ML" "SD-NEST-CHU" 8 0.0))))

(defun sd:img-diagram (pls nsl SW SH pt sc) (sd:dg-draw pls nsl SW SH pt sc nil nil))

;; Khung vien: goc canh dai nhat (rad) + kich thuoc trong khung do (tw dai theo goc, th) + tam vien (toa do that)
(defun sd:tile-frame (pts / a b ang la best lp x0 y0 x1 y1 cl)
  (setq a (last pts))
  (foreach b pts
    (setq la (distance a b))
    (if (or (null best) (> la (car best))) (setq best (list la (angle a b))))
    (setq a b))
  (setq ang (cond (*SD:IFRAME*) ((cadr best))) ; *SD:IFRAME*: luoi rai co goc xac dinh -> moi vien dung chung khung cua luoi (van song song)
        lp (mapcar '(lambda (q) (sd:rot (list (car q) (cadr q)) (- ang))) pts)
        x0 (apply 'min (mapcar 'car lp)) x1 (apply 'max (mapcar 'car lp))
        y0 (apply 'min (mapcar 'cadr lp)) y1 (apply 'max (mapcar 'cadr lp))
        cl (sd:rot (list (/ (+ x0 x1) 2.0) (/ (+ y0 y1) 2.0)) ang))
  (list ang (- x1 x0) (- y1 y0) cl))

;; Dat 1 vien tu anh: copy anh -> xoay (goc nen + 90 neu xep xoay) -> dua tam manh anh ve tam vien -> IMAGECLIP da giac theo vien
(defun sd:img-place (mst pl base cw pts / cp cs e)
  (setq cs (list (+ (cadr mst) (nth 2 pl) (/ (nth 4 pl) 2.0)) (+ (caddr mst) (nth 3 pl) (/ (nth 5 pl) 2.0)) 0.0)
        cp (vla-Copy (car mst)))
  (vla-Rotate cp (vlax-3d-point cs) (+ base (if (nth 6 pl) (/ pi 2.0) 0.0)))
  (vla-Move cp (vlax-3d-point cs) (vlax-3d-point (list (car cw) (cadr cw) 0.0)))
  (vla-put-Layer cp "SD-GACH-ANH")
  (setq e (vlax-vla-object->ename cp))
  (command "_.IMAGECLIP" e "_N" "_P")
  (foreach q pts (command (trans (list (car q) (cadr q) 0.0) 0 1)))
  (command "")
  ;; nho tam vien de SDMOANH tu ghep anh voi polyline vien sau khi chinh bien
  (vl-catch-all-apply 'sd:put-xd
    (list e (list -3 (list "SD_ANH" (cons 1040 (float (car cw))) (cons 1040 (float (cadr cw)))
                           ;; goc xoay anh so voi canh dai vien (99 = luoi chung, khong tu xoay lai)
                           (cons 1040 (if *SD:IFRAME* 99.0 (rem (- (+ base (if (nth 6 pl) (/ pi 2.0) 0.0)) (car (sd:tile-frame pts))) (* 2.0 pi))))))))
  e)

;; Thu tu chay doc theo duong vien: bat dau tu vien trai nhat, moi buoc di sang vien gan nhat chua di (van chay lien tuc quanh vien)
(defun sd:tile-chain (tiles / cur r rest best d)
  (setq rest tiles
        cur (car (sd:sort tiles '(lambda (a b) (if (equal (car (nth 5 a)) (car (nth 5 b)) 1.0)
                                                 (< (cadr (nth 5 a)) (cadr (nth 5 b)))
                                                 (< (car (nth 5 a)) (car (nth 5 b))))))))
  (while cur
    (setq r (cons (cons 0 cur) r) rest (vl-remove cur rest) best nil)
    (foreach x rest
      (setq d (distance (nth 5 cur) (nth 5 x)))
      (if (or (null best) (< d (car best))) (setq best (list d x))))
    (setq cur (cadr best)))
  (reverse r))

;; Thu tu lat ngoang nghoeo: hang (theo y) tu duoi len, hang chan trai -> phai, hang le phai -> trai. tiles = ((id pts ang tw th cw) ...)
(defun sd:tile-order (tiles / rh rows)
  (setq rh (max 1.0 (apply 'min (mapcar '(lambda (r) (min (nth 3 r) (nth 4 r))) tiles))))
  (setq tiles (mapcar '(lambda (r) (cons (fix (+ 0.5 (/ (cadr (nth 5 r)) rh))) r)) tiles))
  (sd:sort tiles '(lambda (a b)
                    (if (= (car a) (car b))
                      (if (= (rem (car a) 2) 0)
                        (< (car (nth 6 a)) (car (nth 6 b)))
                        (> (car (nth 6 a)) (car (nth 6 b))))
                      (< (car a) (car b))))))

(defun c:SDANHDA () (sd:begin) (setq *SD:IFRAME* nil) (sd:anhda nil) (sd:finish))

;; Cat anh da vao cac vien: els = danh sach ename polyline (nil = hoi quet chon). Dung cho SDANHDA va SDGACH (khai bao chung 1 hop thoai)
;; ---- Xep THEO THU TU (van lien tuc) nhung van cat xuyen va lap cho trong, tung tam mot ----
;; Moi tam chi lay tu win vien dau chua xep (cua so); win = 1 la dung thu tu tuyet doi, lon hon thi vien nho phia sau lap vao cho trong con lai.
;; Thu 4 cach cham diem / tach o, chon cach xep duoc nhieu dien tich nhat vao tam do. Tra ve nhu sd:nest-g1
(defun sd:take (lst n / r)
  (while (and lst (> n 0)) (setq r (cons (car lst) r) lst (cdr lst) n (1- n)))
  (reverse r))

(defun sd:nw-slab (part SW SH trim kerf rotok vun / best bs v res a)
  (foreach v '((0 1) (2 1) (0 2) (0 0))
    (setq res (sd:nest-g1 part SW SH trim kerf rotok vun (car v) (cadr v))
          a (apply '+ (mapcar '(lambda (p) (if (and (cadr p) (= (cadr p) 0)) (* (nth 4 p) (nth 5 p)) 0.0)) (car res))))
    (if (or (null bs) (> a bs)) (setq bs a best res)))
  best)

(defun sd:nest-w (items SW SH trim kerf rotok vun win / rest n res spill out cuts remn k ids c r)
  (setq rest items k 0 win (max 1 win))
  (while rest
    (setq n (min win (length rest)) res nil)
    (while (not res)
      (setq res (sd:nw-slab (sd:take rest n) SW SH trim kerf rotok vun)
            spill (vl-some '(lambda (p) (and (cadr p) (> (cadr p) 0))) (car res)))
      (if (and (not spill) (< n (length rest)))
        (setq n (min (length rest) (+ n win)) res nil)))
    (setq ids nil)
    (foreach p (car res)
      (cond ((null (cadr p)) (setq out (cons p out) ids (cons (car p) ids)))
            ((= (cadr p) 0) (setq out (cons (cons (car p) (cons k (cddr p))) out) ids (cons (car p) ids)))))
    (foreach c (caddr res) (if (= (car c) 0) (setq cuts (cons (cons k (cdr c)) cuts))))
    (foreach r (cadddr res) (if (= (car r) 0) (setq remn (cons (cons k (cdr r)) remn))))
    (setq rest (vl-remove-if '(lambda (it) (member (car it) ids)) rest) k (1+ k)))
  (list (reverse out) k (reverse cuts) (reverse remn)))

;;; --------------------------------------------------------------------------
;;;  SDTUDONG - Che do tu dong cho ca phien: sua bien vien (grip, stretch, move...) xong thi anh IMAGECLIP tu cat lai theo bien moi
;;;  Theo doi chung ca ban ve (khong can chon vien), nho trang thai Bat / Tat trong registry nen tu bat khi nap SDOpLat.lsp
;;; --------------------------------------------------------------------------
(defun sd:ud-lay-p (lay) (member (strcase lay) '("SD-GACH" "SD-GACH-CAT" "SD-GACH-VIEN" "SD-GACH-DOC")))

;; Ghi nho polyline vien vua bi sua (chi doc tenh chat nhe; viec nang lam sau khi lenh ket thuc)
(defun sd:ud-dbmod (rx args / obj h)
  (if (and (not *SD:RXBUSY*) args)
    (vl-catch-all-apply
      '(lambda ()
         (setq obj (car args))
         (if (= (type obj) 'ENAME) (setq obj (vlax-ename->vla-object obj)))
         (if (and (= (type obj) 'VLA-OBJECT) (not (vlax-erased-p obj))
                  (= (vla-get-ObjectName obj) "AcDbPolyline") (sd:ud-lay-p (vla-get-Layer obj)))
           (progn (setq h (vla-get-Handle obj))
                  (if (not (member h *SD:RXPEND*)) (setq *SD:RXPEND* (cons h *SD:RXPEND*))))))
      nil)))

;; ---- Lien ket vien <-> anh (khong phu thuoc vi tri hien tai): anh di theo vien khi MOVE / ROTATE, chi cat lai khi bien doi hinh ----
;; *SD:RXMAP* = ((ma-vien ma-anh da-giac goc-anh goc-xoay-anh) ...), lap lai sau cac lenh SD tao / doi vien + anh
(defun sd:ud-adiff (a b / d)
  (setq d (rem (- a b) (* 2.0 pi)))
  (cond ((> d pi) (- d (* 2.0 pi))) ((< d (- pi)) (+ d (* 2.0 pi))) (t d)))

;; Da giac b co phai la da giac a chi tinh tien + xoay (cung thu tu dinh)? Tra ve (tam-cu tam-moi goc-xoay) hoac nil
(defun sd:ud-rigid (a b tol / n c0 c1 th ok i p)
  (if (and a b (= (length a) (length b)) (> (length a) 2))
    (progn
      (setq n (float (length a))
            c0 (list (/ (apply '+ (mapcar 'car a)) n) (/ (apply '+ (mapcar 'cadr a)) n))
            c1 (list (/ (apply '+ (mapcar 'car b)) n) (/ (apply '+ (mapcar 'cadr b)) n))
            th (if (> (distance c0 (car a)) 1e-6)
                 (- (angle c1 (car b)) (angle c0 (car a)))
                 (- (angle (car b) (cadr b)) (angle (car a) (cadr a))))
            ok t i 0)
      (while (and ok (< i (length a)))
        (setq p (polar c1 (+ (angle c0 (nth i a)) th) (distance c0 (nth i a))))
        (if (> (distance p (nth i b)) tol) (setq ok nil))
        (setq i (1+ i)))
      (if ok (list c0 c1 th)))))

;; Anh dung tam vien nam trong da giac (hoac gan nhat trong ban kinh): il = ((ma-anh ename cx cy) ...), bb = (x0 y0 x1 y1)
(defun sd:ud-pick (pts bb il / cx cy rad r best d)
  (setq cx (/ (apply '+ (mapcar 'car pts)) (float (length pts)))
        cy (/ (apply '+ (mapcar 'cadr pts)) (float (length pts)))
        rad (apply 'max (mapcar '(lambda (q) (distance (list cx cy) q)) pts)))
  (foreach im il
    (if (and (null r) (<= (car bb) (nth 2 im) (caddr bb)) (<= (cadr bb) (nth 3 im) (cadddr bb))
             (sd:inpoly (list (nth 2 im) (nth 3 im)) pts))
      (setq r im))
    (setq d (distance (list cx cy) (list (nth 2 im) (nth 3 im))))
    (if (and (<= d (+ rad 50.0)) (or (null best) (< d (car best)))) (setq best (cons d im))))
  (cond (r) ((cdr best))))

;; Ghi nho cap vien - anh va hinh hoc hien tai cua anh
(defun sd:ud-mapset (h im pts / g)
  (setq g (sd:im-geom im)
        *SD:RXMAP* (cons (list h (cdr (assoc 5 (entget im))) pts (car g) (cadr g))
                         (vl-remove (assoc h *SD:RXMAP*) *SD:RXMAP*))))

;; Trang thai anh so voi luc ghi nho: FOLLOW = anh chua di (dich theo vien), SKIP = anh da di cung vien (vd chon ca anh khi MOVE), OTHER = anh bi sua rieng
(defun sd:ud-img-state (im ent rg / g o a e)
  (setq g (sd:im-geom im) o (car g) a (cadr g)
        e (polar (cadr rg) (+ (angle (car rg) (nth 3 ent)) (caddr rg)) (distance (car rg) (nth 3 ent))))
  (cond ((and (< (distance o (nth 3 ent)) 0.05) (< (abs (sd:ud-adiff a (nth 4 ent))) 1e-5)) 'FOLLOW)
        ((and (< (distance o e) 0.05) (< (abs (sd:ud-adiff a (+ (nth 4 ent) (caddr rg)))) 1e-5)) 'SKIP)
        (t 'OTHER)))

;; Dich + xoay anh theo vien: p' = tam-moi + R(goc) (p - tam-cu); duong cat IMAGECLIP nam trong anh nen di theo
(defun sd:ud-follow (im rg / o c0 c1 th)
  (setq o (vlax-ename->vla-object im) c0 (car rg) c1 (cadr rg) th (caddr rg))
  (if (> (abs th) 1e-9) (vla-Rotate o (vlax-3d-point (car c0) (cadr c0) 0.0) th))
  (vla-Move o (vlax-3d-point (car c0) (cadr c0) 0.0) (vlax-3d-point (car c1) (cadr c1) 0.0))
  (setq *SD:IMCLIPS* nil))

;; Cap nhat tam vien ghi trong SD_ANH (de SDMOANH / SDRON / SDDICHVAN con tim ra anh sau khi vien da di xa)
(defun sd:ud-setctr (im c / xd)
  (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget im '("SD_ANH"))))))
  (if (>= (length xd) 3)
    (vl-catch-all-apply 'sd:put-xd
      (list im (list -3 (list "SD_ANH" (cons 1040 (float (car c))) (cons 1040 (float (cadr c))) (cons 1040 (nth 2 xd))))))))

(defun sd:ud-ended (rx cmd / hs ims e pts im n os ce oa ent rg st fr)
  (cond
    (*SD:RXBUSY*)
    ;; lenh cua SDOpLat tu lo anh va hatch; undo / redo khong xu ly
    ((wcmatch (strcase (car cmd)) "SD*,U,UNDO,OOPS,REDO,MREDO,*SAVE,CLOSE,QUIT")
     (setq *SD:RXPEND* nil)
     ;; lenh vua tao / doi vien + anh: lap lai ban do lien ket vien - anh de MOVE / ROTATE vien sau do keo anh di theo
     (if (wcmatch (strcase (car cmd)) "SDANHDA,SDMOANH,SDRON,SDDOCDA,SDRAITAM,SDLOT,SDLENH,SDXOAVIEN,SDDICHVAN,SDMAP*,SDPHUONGAN,SDTHANGDA")
       (vl-catch-all-apply 'sd:ud-snap nil)))
    ((null *SD:RXPEND*))
    (t
     (setq *SD:RXBUSY* t hs *SD:RXPEND* *SD:RXPEND* nil n 0 os (getvar "OSMODE") ce (getvar "CMDECHO") *SD:IMCLIPS* nil)
     (setvar "OSMODE" 0) (setvar "CMDECHO" 0)
     (vl-catch-all-apply
       '(lambda ()
          (foreach h hs
            (if (and (setq e (handent h)) (entget e) (= (cdr (assoc 0 (entget e))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget e))))))
              (progn
                (setq pts (sd:curve-pts e) ent (assoc h *SD:RXMAP*) im nil rg nil *SD:IFRAME* nil)
                ;; anh theo ban do lien ket (khong phu thuoc vi tri); khong co thi tim theo vi tri nhu truoc
                (if (and ent (setq im (handent (cadr ent))) (null (entget im))) (setq im nil))
                (if (null im)
                  (progn
                    (if (null ims) (setq ims (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH"))))))
                    (setq im (if ims (sd:im-find pts ims)))))
                (setq oa (cdr (assoc h *SD:RXANG*)) fr (sd:tile-frame pts)
                      *SD:RXANG* (cons (cons h (car fr)) (vl-remove (assoc h *SD:RXANG*) *SD:RXANG*)))
                (cond
                  ((null im))
                  ;; vien chi tinh tien / xoay (MOVE, ROTATE): anh di theo vien, khong can cat lai
                  ((and ent (equal (cadr ent) (cdr (assoc 5 (entget im)))) (setq rg (sd:ud-rigid (caddr ent) pts 0.2)))
                   (if (and (< (distance (car rg) (cadr rg)) 1e-6) (< (abs (caddr rg)) 1e-9))
                     nil
                     (progn
                       (setq st (sd:ud-img-state im ent rg))
                       (cond ((= st 'FOLLOW) (sd:ud-follow im rg) (setq n (1+ n)))
                             ((= st 'SKIP))
                             (t (sd:im-reclip im (sd:inset-pts pts (/ (cond (*SD:IRON*) (0.0)) 2.0)) 10.0 oa) (setq n (1+ n))))
                       (sd:ud-setctr im (cadddr fr))))
                   (sd:ud-mapset h im pts))
                  ;; bien doi hinh (grip, stretch...): cat lai anh theo bien moi
                  (t
                   (sd:im-reclip im (sd:inset-pts pts (/ (cond (*SD:IRON*) (0.0)) 2.0)) 10.0 oa)
                   (setq n (1+ n))
                   (sd:ud-setctr im (cadddr fr))
                   (sd:ud-mapset h im pts))))))
       nil)
       nil)
     (setvar "OSMODE" os) (setvar "CMDECHO" ce)
     (if (> n 0) (princ (strcat "\n[SD] Tu dong: da dich / cat lai anh " (itoa n) " vien theo vien moi.")))
     (if *SD:XOAYHINT*
       (progn (princ "\n[SD] Co vien het kho theo chieu van hien tai nhung xoay 90 do thi du: chay SDMOANH va chon Hoi / Tu xoay, hoac doi SDMOANH > Het kho thanh Tu xoay de SDTUDONG tu xoay.")
              (setq *SD:XOAYHINT* nil)))
     (setq *SD:RXBUSY* nil))))

;; Goc canh dai hien tai cua cac vien + ban do lien ket vien - anh (goi khi bat SDTUDONG, khi nap, va sau cac lenh SD tao / doi vien + anh)
(defun sd:ud-snap (/ ss ims i e pts il xd bb im h)
  (setq *SD:RXANG* nil *SD:IFRAME* nil *SD:RXMAP* nil)
  (setq *SD:IMCLIPS* nil)
  (foreach c (sd:im-clips)
    (setq il (cons (list (cdr (assoc 5 (entget (car c)))) (car c) (cadr c) (caddr c)) il)))
  (if (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT,SD-GACH-VIEN,SD-GACH-DOC") (-4 . "&") (70 . 1))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i))
        (vl-catch-all-apply
          '(lambda ()
             (setq h (cdr (assoc 5 (entget e))) pts (sd:curve-pts e)
                   *SD:RXANG* (cons (cons h (car (sd:tile-frame pts))) *SD:RXANG*))
             (if il
               (progn
                 (setq bb (list (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts))
                                (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts))))
                 (if (setq im (sd:ud-pick pts bb il)) (sd:ud-mapset h (cadr im) pts)))))
          nil))))
  (length *SD:RXANG*))


(defun sd:ud-on ()
  (if (not *SD:RXDB*)
    (setq *SD:RXDB* (vlr-acdb-reactor "SD-tudong" '((:vlr-objectModified . sd:ud-dbmod)))
          *SD:RXCMD* (vlr-command-reactor "SD-tudong" '((:vlr-commandEnded . sd:ud-ended)))
          *SD:RXPEND* nil *SD:RXBUSY* nil))
  t)

(defun sd:ud-off ()
  (if *SD:RXDB* (vl-catch-all-apply 'vlr-remove (list *SD:RXDB*)))
  (if *SD:RXCMD* (vl-catch-all-apply 'vlr-remove (list *SD:RXCMD*)))
  (setq *SD:RXDB* nil *SD:RXCMD* nil *SD:RXPEND* nil *SD:RXBUSY* nil *SD:RXMAP* nil)
  nil)

(defun sd:ud-flag (/ v)
  (setq v (vl-catch-all-apply 'vl-registry-read (list "HKEY_CURRENT_USER\\Software\\SDOpLat" "AutoSync")))
  (and (not (vl-catch-all-error-p v)) (= v "1")))
(defun sd:ud-flag-set (on)
  (vl-catch-all-apply 'vl-registry-write (list "HKEY_CURRENT_USER\\Software\\SDOpLat" "AutoSync" (if on "1" "0"))))

;; Goi khi nap SDOpLat.lsp (moi ban ve): bat lai neu lan truoc da bat
(defun sd:ud-autoload ()
  (if (sd:ud-flag) (progn (sd:ud-on) (sd:ud-snap) (princ "\n[SD] Tu dong cat lai anh khi sua bien vien: BAT (SDTUDONG de tat)."))))

(defun c:SDTUDONG (/ n)
  (sd:begin)
  (cond
    (*SD:RXDB*
     (sd:ud-off) (sd:ud-flag-set nil)
     (princ "\n[SD] Da TAT che do tu dong cat lai anh khi sua bien vien (nho cho cac lan mo sau)."))
    (t
     (sd:ud-on) (sd:ud-flag-set t) (setq n (sd:ud-snap))
     (princ (strcat "\n[SD] Da BAT che do tu dong cho ca phien va cac ban ve mo sau: MOVE / ROTATE vien thi anh di theo vien; grip / stretch thi anh IMAGECLIP tu cat lai theo bien moi, "
                    "hatch lien ket tu theo. Dang theo doi " (itoa n) " vien hien co va ca vien tao them sau. Chay lai SDTUDONG de tat."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDRONIN - Cho ron / duong vien hien ra khi IN: doi mau + be rong net cac layer vien, dua duong vien len tren anh va hatch
;;;  (duong vien mau toi bi in thanh den chim vao da toi; net qua mong bi mat khi in co nho; anh che duong vien)
;;; --------------------------------------------------------------------------
(setq *SD:RONLAY* '("SD-GACH" "SD-GACH-CAT" "SD-GACH-VIEN" "SD-GACH-DOC"))

;; Be rong net hop le gan nhat (mm * 100)
(defun sd:lw-near (lw / best)
  (foreach v '(0 5 9 13 15 18 20 25 30 35 40 50 53 60 70 80 90 100 106 120 140 158 200 211)
    (if (or (null best) (< (abs (- v lw)) (abs (- best lw)))) (setq best v)))
  best)

;; Bang ma vat lieu -> mau tu chuoi "G1=Den;G2=Trang": (("G1" . 250) ("G2" . 255))
(defun sd:ronin-map (str / r kv)
  (foreach x (sd:split str ";")
    (if (setq kv (sd:split x "="))
      (if (and (= (length kv) 2) (member (strcase (cadr kv)) '("TRANG" "DEN")))
        (setq r (cons (cons (strcase (car kv)) (if (= (strcase (cadr kv)) "TRANG") 255 250)) r)))))
  r)

;; Dat mau / net rieng cho 1 polyline vien (col / lw100 = nil: khong co, tra ve theo layer). Tra ve (mau-cu net-cu) de khoi phuc dung
(defun sd:ronin-ent (e col lw100 / ed new g o62 o370)
  (setq ed (entget e '("SD_TILE")) o62 (cdr (assoc 62 ed)) o370 (cdr (assoc 370 ed)))
  (foreach g ed
    (cond ((member (car g) '(62 370)))
          (t (setq new (cons g new))
             (if (= (car g) 8)
               (progn (if col (setq new (cons (cons 62 col) new)))
                      (if lw100 (setq new (cons (cons 370 lw100) new))))))))
  (entmod (reverse new))
  (list o62 o370))

;; Polyline vien do SDANHDA cat anh nhung nam ngoai cac layer SD-GACH* (VD boundary tu hatch): nho handle de ron in / SDRONIN / SDIN cung tac dong
(defun sd:ron-extra (/ r e)
  (foreach h (vlax-ldata-get "SD" "RON-EXTRA")
    (if (and (setq e (handent h)) (entget e) (= (cdr (assoc 0 (entget e))) "LWPOLYLINE")) (setq r (cons h r))))
  (reverse r))
(defun sd:ron-extra-add (els / lst ed hd)
  (setq lst (sd:ron-extra))
  (foreach e els
    (setq ed (entget e) hd (cdr (assoc 5 ed)))
    (if (and (not (member (strcase (cdr (assoc 8 ed))) *SD:RONLAY*)) (not (member hd lst)))
      (setq lst (cons hd lst))))
  (vlax-ldata-put "SD" "RON-EXTRA" lst)
  lst)

(defun sd:imgframe (mau / ifo ikh)
  (cond
    ((= mau "Khoiphuc")
     (if (and (setq ifo (sd:cfg "RONIN-IMGF" -1)) (>= ifo 0))
       (progn (setvar "IMAGEFRAME" ifo) (sd:cfg-put "RONIN-IMGF" -1))))
    (t
     (setq ikh (sd:cfg "RONIN-KHUNG" "Khongin"))
     (if (< (sd:cfg "RONIN-IMGF" -1) 0) (sd:cfg-put "RONIN-IMGF" (getvar "IMAGEFRAME")))
     (setvar "IMAGEFRAME" (cond ((= ikh "An") 0) ((= ikh "Giu") 1) (2))))))

(defun sd:ronin-apply (mau lw mapstr front / lays old l n ss i lo mp nm2 xd col sv e h old2 nxe)
  (sd:imgframe mau)
  (setq n 0 lays (vla-get-Layers (sd:doc)) old (vlax-ldata-get "SD" "RONIN-OLD") sv (vlax-ldata-get "SD" "RONIN-ENT"))
  (foreach nm *SD:RONLAY*
    (if (tblsearch "LAYER" nm)
      (progn
        (setq l (vla-Item lays nm))
        (cond
          ((= mau "Khoiphuc")
           (if (setq lo (assoc nm old))
             (progn (vla-put-Color l (cadr lo)) (vla-put-Lineweight l (caddr lo)) (setq n (1+ n)))))
          (t
           (if (not (assoc nm old))
             (setq old (cons (list nm (vla-get-Color l) (vla-get-Lineweight l)) old)))
           (vla-put-Color l (if (= mau "Trang") 255 250))
           (vla-put-Lineweight l (sd:lw-near (fix (+ 0.5 (* 100.0 lw)))))
           (vla-put-Plottable l :vlax-true)
           (setq n (1+ n)))))))
  (setq mp (if (and (/= mau "Khoiphuc") mapstr (/= mapstr "")) (sd:ronin-map mapstr)))
  (cond
    ;; khoi phuc: tra lai dung mau / net rieng cu cua tung vien da bi doi (khong dung vao mau do nguoi dung tu dat)
    ((= mau "Khoiphuc")
     (setq nm2 0)
     (if sv
       (foreach r sv
         (if (setq e (handent (car r))) (progn (sd:ronin-ent e (cadr r) (caddr r)) (setq nm2 (1+ nm2)))))
       ;; chua co ban ghi (ban cu): bo mau rieng cua moi vien
       (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") '(-3 ("SD_TILE")) (cons 8 (sd:join *SD:RONLAY* ",")))))
         (progn (setq i 0) (repeat (sslength ss) (sd:ronin-ent (ssname ss i) nil nil) (setq i (1+ i) nm2 (1+ nm2))))))
     (vlax-ldata-put "SD" "RONIN-ENT" nil)
     (if (> nm2 0) (princ (strcat "\n[SD] Da tra mau / net rieng cu cho " (itoa nm2) " vien."))))
    (mp
     (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") '(-3 ("SD_TILE")) (cons 8 (sd:join *SD:RONLAY* ",")))))
       (progn
         (setq i 0 nm2 0)
         (repeat (sslength ss)
           (setq e (ssname ss i) i (1+ i)
                 xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
           (if (and xd (setq col (cdr (assoc (strcase (car xd)) mp))))
             (progn
               (setq old2 (sd:ronin-ent e col (sd:lw-near (fix (+ 0.5 (* 100.0 lw))))) h (cdr (assoc 5 (entget e))) nm2 (1+ nm2))
               (if (not (assoc h sv)) (setq sv (cons (cons h old2) sv))))))
         (vlax-ldata-put "SD" "RONIN-ENT" sv)
         (if (> nm2 0) (princ (strcat "\n[SD] Mau rieng theo vat lieu: " (itoa nm2) " vien.")))))))
  ;; polyline ngoai layer SD-GACH* da cat anh bang SDANHDA: dat mau / net rieng tung polyline (luu mau cu de khoi phuc)
  (if (/= mau "Khoiphuc")
    (progn
      (setq nxe 0)
      (foreach hd (sd:ron-extra)
        (setq e (handent hd)
              old2 (sd:ronin-ent e (if (= mau "Trang") 255 250) (sd:lw-near (fix (+ 0.5 (* 100.0 lw)))))
              nxe (1+ nxe))
        (if (not (assoc hd sv)) (setq sv (cons (cons hd old2) sv))))
      (vlax-ldata-put "SD" "RONIN-ENT" sv)
      (if (> nxe 0) (princ (strcat "\n[SD] Polyline vien ngoai layer SD-GACH (da cat anh): " (itoa nxe) " vien dat mau / net ron.")))))
  (if (/= mau "Khoiphuc") (vlax-ldata-put "SD" "RONIN-OLD" old))
  (if (and (= mau "Khoiphuc") old) (vlax-ldata-put "SD" "RONIN-OLD" nil))
  (if (and front (/= mau "Khoiphuc"))
    (progn
      (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 (sd:join *SD:RONLAY* ",")))))
      (foreach hd (sd:ron-extra) (setq ss (cond (ss) ((ssadd)))) (ssadd (handent hd) ss))
      (if ss (command "_.DRAWORDER" ss "" "_F"))))
  (command "_.REGENALL")
  (princ (strcat "\n[SD] " (itoa n) " layer vien: "
                 (cond ((= mau "Trang") (strcat "mau trang thuan, net " (sd:num lw) " mm"))
                       ((= mau "Den") (strcat "mau den, net " (sd:num lw) " mm"))
                       (t "da khoi phuc mau va net cu"))
                 (if (and front (/= mau "Khoiphuc")) "; duong vien da dua len tren anh va hatch" "") "."))
  n)

(defun c:SDRONIN ()
  (sd:begin)
  (if (sd:dlg "Ron hien ra khi in (SDRONIN)"
              (list (list "mau" "Mau duong ron / vien tren cac layer vien" 'kw (sd:cfg "RONIN-MAU" "Trang")
                          '(("Trang" . "Trang thuan (ACI 255): hien tren da / anh toi khi in")
                            ("Den" . "Den (ACI 250)")
                            ("Khoiphuc" . "Khoi phuc mau va net cu")))
                    (list "lw" "Be rong net khi in (mm)" 'real (sd:cfg "RONIN-LW" 0.25) nil '("mau" "Trang" "Den"))
                    (list "map" "Theo vat lieu: ma=mau, VD G1=Den;G2=Trang (de trong = cung 1 mau cho tat ca)" 'str (sd:cfg "RONIN-MAP" "") nil '("mau" "Trang" "Den"))
                    (list "front" "Dua duong vien (polyline) len tren anh va hatch" 'tog t)
                    (list "khung" "Khung vien den cua anh da (IMAGEFRAME)" 'kw (sd:cfg "RONIN-KHUNG" "Khongin")
                          '(("Khongin" . "Hien khi ve, khong in (IMAGEFRAME 2)") ("An" . "An han (IMAGEFRAME 0)") ("Giu" . "Giu nguyen khung (IMAGEFRAME 1)"))
                          '("mau" "Trang" "Den"))))
    (progn
      (sd:cfg-put "RONIN-KHUNG" (cond ((sd:v "khung")) ("Khongin")))
      (sd:cfg-put "RONIN-MAU" (sd:v "mau")) (sd:cfg-put "RONIN-LW" (cond ((sd:v "lw")) (0.25)))
      (sd:cfg-put "RONIN-MAP" (cond ((sd:v "map")) ("")))
      (sd:ronin-apply (sd:v "mau") (cond ((sd:v "lw")) (0.25)) (cond ((sd:v "map")) ("")) (sd:v "front"))
      (if (/= (sd:v "mau") "Khoiphuc")
        (princ "\n   Khi in: dung bang net acad.ctb (mau ACI 255 in dung mau trang); KHONG dung monochrome.ctb vi se doi ron thanh den, chim vao da toi. Tich 'Plot object lineweights'. Neu in nho (Fit to paper) thi tang be rong net hoac ron."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  Thu vien vat lieu: nho thong so lan truoc theo ma vat lieu (cfg "VL-MAU", moi ban ve), hien danh sach de chon nhanh
;;;  Moi muc: (ma ten W H day ron khe kieu). Moi nhat nam dau, toi da 12 muc.
;;; --------------------------------------------------------------------------
(defun sd:vl-load () (sd:cfg "VL-MAU" nil))

(defun sd:vl-save (mat name W H thk jt gap pat / lst)
  (if (and mat (/= mat ""))
    (progn
      (setq lst (vl-remove-if '(lambda (r) (= (strcase (car r)) (strcase mat))) (sd:vl-load)))
      (sd:cfg-put "VL-MAU" (sd:take (cons (list mat name W H thk jt gap pat) lst) 12)))))

(defun sd:vl-line (k r)
  (strcat "\n  " (itoa k) ". " (car r) "  " (cadr r) "  [" (rtos (nth 2 r) 2 0) "x" (rtos (nth 3 r) 2 0) "x" (rtos (nth 4 r) 2 0)
          "  ron " (rtos (nth 5 r) 2 1) "  khe " (rtos (nth 6 r) 2 1) "  " (nth 7 r) "]"))

(defun sd:vl-show (lst / k)
  (setq k 0)
  (foreach r lst (setq k (1+ k)) (princ (sd:vl-line k r))))

;; hien danh sach, nhap so de dien san cac gia tri mac dinh cua hop thoai ngay sau do; Enter = nhap moi
(defun sd:vl-pick (/ lst n r)
  (if (setq lst (sd:vl-load))
    (progn
      (princ "\nVat lieu da dung (moi nhat truoc):")
      (sd:vl-show lst)
      (setq n (getint "\nChon so de dung lai thong so <Enter = nhap moi>: "))
      (if (and n (>= n 1) (<= n (length lst)))
        (progn
          (setq r (nth (1- n) lst))
          (setq *SD:GCODE* (nth 0 r) *SD:GNAME* (nth 1 r) *SD:GW* (nth 2 r) *SD:GH* (nth 3 r) *SD:GT* (nth 4 r)
                *SD:GJ* (nth 5 r) *SD:GGAP* (nth 6 r) *SD:GPAT* (nth 7 r))
          (if (member (nth 7 r) '("Thang" "Sole")) (sd:cfg-put "LOT-PAT" (nth 7 r)))
          (princ (strcat "\n[SD] Dung lai: " (car r) " - sua trong hop thoai neu can."))
          t)))))

(defun c:SDVATLIEU (/ lst n)
  (sd:begin)
  (if (null (setq lst (sd:vl-load)))
    (princ "\n[SD] Chua nho vat lieu nao. Chay SDGACH hoac SDLOT mot lan, thong so se duoc luu lai.")
    (progn
      (princ "\nVat lieu da nho:")
      (sd:vl-show lst)
      (setq n (getint "\nNhap so de XOA khoi danh sach <Enter = thoat>: "))
      (if (and n (>= n 1) (<= n (length lst)))
        (progn
          (sd:cfg-put "VL-MAU" (vl-remove (nth (1- n) lst) lst))
          (princ (strcat "\n[SD] Da xoa " (car (nth (1- n) lst)) " khoi danh sach."))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDXOAVIEN - Go bo vien: xoa cung luc polyline vien + anh + hatch + so hieu T.. trong vung chon,
;;;  de lo ra chi tiet nam duoi (mat cat mui bac...). Moi vien la nhieu doi tuong rieng (polyline, anh, hatch), lenh nay xoa gon 1 lan
;;; --------------------------------------------------------------------------
(defun sd:hatch-center (e / o bb mn mx)
  (setq o (vlax-ename->vla-object e))
  (vla-GetBoundingBox o 'mn 'mx)
  (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx))
  (list (/ (+ (car mn) (car mx)) 2.0) (/ (+ (cadr mn) (cadr mx)) 2.0)))

(defun c:SDXOAVIEN (/ ss i e ed lay polys ents ims hs txs pts im h c n k)
  (sd:begin)
  (princ "\nChon vung can go bo vien (quet cua so; xoa polyline vien + anh + hatch + so hieu T.. cua cac vien trong vung): ")
  (if (setq ss (ssget))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) ed (entget e) lay (strcase (cdr (assoc 8 ed))))
        (cond
          ((and (= (cdr (assoc 0 ed)) "LWPOLYLINE") (member lay *SD:RONLAY*) (= 1 (logand 1 (cdr (assoc 70 ed)))))
           (setq polys (cons e polys)))
          ((or (and (= (cdr (assoc 0 ed)) "IMAGE") (= lay "SD-GACH-ANH"))
               (and (= (cdr (assoc 0 ed)) "HATCH") (= lay "SD-GACH-VAN")))
           (setq ents (cons e ents)))))
      ;; anh / hatch / so hieu thuoc cac vien da chon nhung nam ngoai vung quet
      (setq ims (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH"))))
            hs  (ssget "_X" '((0 . "HATCH") (8 . "SD-GACH-VAN")))
            txs (ssget "_X" '((0 . "TEXT") (8 . "SD-CHU") (1 . "T#*"))))
      (foreach pe polys
        (setq pts (sd:curve-pts pe))
        (if (and ims (setq im (sd:im-find pts ims)) (not (member im ents))) (setq ents (cons im ents)))
        (if hs
          (progn (setq k 0)
                 (repeat (sslength hs)
                   (setq h (ssname hs k) k (1+ k))
                   (if (and (not (member h ents)) (sd:inpoly (sd:hatch-center h) pts)) (setq ents (cons h ents))))))
        (if txs
          (progn (setq k 0)
                 (repeat (sslength txs)
                   (setq h (ssname txs k) k (1+ k) c (cdr (assoc 10 (entget h))))
                   (if (and (not (member h ents)) (sd:inpoly (list (car c) (cadr c)) pts)) (setq ents (cons h ents)))))))
      (setq n 0)
      (foreach x (append polys ents) (if (entget x) (progn (entdel x) (setq n (1+ n)))))
      (princ (strcat "\n[SD] Da go " (itoa (length polys)) " vien (" (itoa n) " doi tuong gom polyline, anh, hatch, so hieu): chi tiet nam duoi da lo ra. Hoan lai bang UNDO.")))
    (princ "\n[SD] Chua chon gi."))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDLOT - Chay mot lan cho nhieu phong / khu vuc: rai vien (SDGACH) cho tung vung, chon diem bat dau tot nhat tu dong,
;;;  ghi ten khu vuc, thong ke tung vung + tong, kiem tra vien cat hep, (tuy chon) cat anh va hatch van cho tat ca
;;; --------------------------------------------------------------------------
;; Tach cac polyline kin thanh vung lat va lo / cot: da giac nam tron trong da giac khac o do sau le la lo, chan la vung
;; Tra ve ((ename-vung (ename-lo ...)) ...)
(defun sd:lot-split (ss / pl i e pts dp par anc r)
  (setq i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) pts (sd:curve-pts e))
    (setq pl (cons (list e pts (abs (sd:area pts))) pl)))
  (foreach p pl
    (setq dp 0 par nil)
    (foreach q pl
      (if (and (not (eq (car p) (car q))) (> (nth 2 q) (nth 2 p))
               (vl-every '(lambda (v) (sd:inpoly v (nth 1 q))) (nth 1 p)))
        (progn (setq dp (1+ dp))
               (if (or (null par) (< (nth 2 q) (nth 2 par))) (setq par q)))))
    (setq anc (cons (list (car p) dp (if par (car par))) anc)))
  (foreach x anc
    (if (= (rem (cadr x) 2) 0)
      (setq r (cons (list (car x)
                          (mapcar 'car (vl-remove-if-not '(lambda (y) (and (= (rem (cadr y) 2) 1) (eq (caddr y) (car x)))) anc)))
                    r))))
  (reverse r))

;; Diem bat dau tot nhat (toa do WCS, goc vien trai-duoi cua luoi) cho vung outer-pts tru cac lo, luoi W x H, ron jt, goc ang (rad)
(defun sd:lot-best (outer-pts holes W H jt ang hep q / rp rh cands res)
  (setq rp (mapcar '(lambda (p) (sd:rot p (- ang))) outer-pts)
        rh (mapcar '(lambda (hp) (mapcar '(lambda (p) (sd:rot p (- ang))) hp)) holes)
        cands (sd:od-cands rp W H jt q))
  (foreach c cands (setq res (cons (list c (sd:od-eval rp rh W H jt (cadr c) (caddr c) hep)) res)))
  (setq res (car (sd:sort res 'sd:od-less)))
  (list (sd:rot (list (cadr (car res)) (caddr (car res))) ang) (car (car res)) (cadr res)))

(defun c:SDLOT (/ cpt ss rooms rm k outer holes mat name W H thk jt gap pat ang start q hep nhan anh van sc o b last news
                  nf nc ns arr cpa xd rows tn tc tf tarea twaste fn f e r pts lbl allnew)
  (sd:begin)
  (setq sc (sd:sc))
  (sd:vl-pick)
  (if (sd:dlg "Chay lo nhieu phong (SDLOT)"
              (list (list "mat" "Ma vat lieu" 'str (cond (*SD:GCODE*) ("G1")))
                    (list "name" "Ten vat lieu" 'str (cond (*SD:GNAME*) ("Granite 600x600x20")))
                    (list "W" "Vien thanh pham - ngang W (mm)" 'real (cond (*SD:GW*) (600.0)))
                    (list "H" "Vien thanh pham - dung H (mm)" 'real (cond (*SD:GH*) (600.0)))
                    (list "thk" "Chieu day da / gach (mm)" 'real (cond (*SD:GT*) (20.0)))
                    (list "jt" "Be rong mach / ron (mm)" 'real0 (cond (*SD:GJ*) ((sd:cfg "RON-CU" 2.0))))
                    (list "gap" "Khe sat tuong va quanh lo (mm)" 'real0 (cond (*SD:GGAP*) (0.0)))
                    (list "pat" "Kieu lat" 'kw (sd:cfg "LOT-PAT" "Thang") '(("Thang" . "Thang") ("Sole" . "So le (diem bat dau = tam vung)")))
                    (list "ang" "Goc xoay luoi (do)" 'real0 (sd:cfg "LOT-ANG" 0.0))
                    (list "start" "Diem bat dau tung vung" 'kw (sd:cfg "LOT-START" "Tot")
                          '(("Tot" . "Tot nhat (it vien hep, it vien cat; chi lat thang)") ("Tam" . "Tam vung") ("Goc" . "Goc trai-duoi vung")
                            ("Chung" . "Mot diem goc chung cho moi vung: luoi ron lien tuc xuyen cac phong (chon diem sau)")))
                    (list "q" "Do ky khi chon diem tot nhat" 'kw (sd:cfg "LOT-Q" "Nhanh")
                          '(("Nhanh" . "Nhanh: 6 diem") ("Ky" . "Ky: them 25 diem quet")) '("start" "Tot"))
                    (list "hep" "Vien cat hep hon (mm) tinh la vun" 'real (sd:cfg "LOT-HEP" 50.0))
                    (list "nhan" "Ghi ten khu vuc (KV1, KV2...) va dien tich" 'tog t)
                    (list "anh" "Sau do cat anh tam da cho tat ca cac vien (SDANHDA, hoi 1 lan)" 'tog nil)
                    (list "van" "Sau do hatch van da cho cac vien (SDVANDA)" 'tog nil)))
    (progn
      (setq mat (sd:v "mat") name (sd:v "name") W (sd:v "W") H (sd:v "H") thk (sd:v "thk") jt (sd:v "jt") gap (sd:v "gap")
            pat (sd:cfg-put "LOT-PAT" (sd:v "pat")) ang (sd:cfg-put "LOT-ANG" (cond ((sd:v "ang")) (0.0)))
            start (sd:cfg-put "LOT-START" (sd:v "start")) q (sd:cfg-put "LOT-Q" (cond ((sd:v "q")) ("Nhanh")))
            hep (sd:cfg-put "LOT-HEP" (sd:v "hep")) nhan (sd:v "nhan") anh (sd:v "anh") van (sd:v "van")
            *SD:GCODE* mat *SD:GNAME* name *SD:GW* W *SD:GH* H *SD:GJ* (sd:cfg-put "RON-CU" jt) *SD:GGAP* gap *SD:GT* thk)
      (sd:vl-save mat name W H thk jt gap pat)
      (princ "\nQuet chon tat ca polyline kin: bien cac phong / khu vuc (lo, cot nam trong se tu nhan la lo): ")
      (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
        (progn
          (if (= start "Chung")
            (if (setq cpt (sd:getpt "\nDiem goc luoi chung (goc duoi-trai cua mot vien hoac giao diem ron): " nil))
              (setq cpt (sd:2d cpt))
              (progn (princ "\n[SD] Chua chon diem chung: dung goc trai-duoi tung vung.") (setq start "Goc"))))
          (setq rooms (sd:lot-split ss) k 0 tn 0 tc 0 tf 0 tarea 0.0 twaste 0.0 *SD:NBRUN* t)
          (princ (strcat "\n[SD] " (itoa (length rooms)) " khu vuc, " (itoa (- (sslength ss) (length rooms))) " lo / cot."))
          (foreach rm rooms
            (setq k (1+ k) outer (car rm) holes (cadr rm) pts (sd:curve-pts outer) o nil lbl "")
            (cond ((and (= start "Tot") (= pat "Thang"))
                   (setq b (sd:lot-best pts (mapcar 'sd:curve-pts holes) W H jt (* pi (/ ang 180.0)) hep (if (= q "Ky") 1 0))
                         o (car b) lbl (strcat (cadr b) ", " (itoa (cadr (caddr b))) " cat")))
                  ((= start "Chung") (setq o cpt lbl "luoi chung"))
                  ((= start "Goc")
                   (setq o (sd:rot (list (apply 'min (mapcar 'car (mapcar '(lambda (p) (sd:rot p (- (* pi (/ ang 180.0))))) pts)))
                                         (apply 'min (mapcar 'cadr (mapcar '(lambda (p) (sd:rot p (- (* pi (/ ang 180.0))))) pts))))
                                   (* pi (/ ang 180.0)))
                         lbl "goc")))
            (setq last (entlast)
                  *SD:GBATCH* t *SD:GOUTER* outer *SD:GHOLES* holes *SD:GSTART* o
                  *SD:BATCH* (list (cons "MAT" mat) (cons "NAME" name) (cons "W" (sd:rtos W 3)) (cons "H" (sd:rtos H 3))
                                   (cons "THK" (sd:rtos thk 3)) (cons "JT" (sd:rtos jt 3)) (cons "GAP" (sd:rtos gap 3))
                                   (cons "PAT" pat) (cons "ANG" (sd:rtos ang 3)) (cons "AL" (if (or o (= start "Goc")) "Goc" "Mach"))
                                   (cons "ANH" "0"))
                  r (vl-catch-all-apply 'c:SDGACH nil)
                  *SD:GBATCH* nil *SD:GOUTER* nil *SD:GHOLES* nil *SD:GSTART* nil *SD:BATCH* nil)
            (if (vl-catch-all-error-p r)
              (princ (strcat "\n[SD] KV" (itoa k) ": khong chia duoc (" (vl-catch-all-error-message r) ")."))
              (progn
                (setq news (sd:gach-new last) nf 0 nc 0 ns 0 arr 0.0 cpa 0.0)
                (foreach e news
                  (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
                  (if (and xd (/= (nth 1 xd) "X"))
                    (progn
                      (setq arr (+ arr (nth 5 xd)))
                      (if (= (nth 1 xd) "F")
                        (setq nf (1+ nf))
                        (progn (setq nc (1+ nc) cpa (+ cpa (nth 5 xd)))
                               (if (< (min (nth 3 xd) (nth 4 xd)) hep) (setq ns (1+ ns))))))))
                (setq allnew (append allnew news)
                      tn (+ tn 1) tf (+ tf nf) tc (+ tc nc)
                      twaste (+ twaste (- (* nc W H) cpa)) tarea (+ tarea arr))
                (setq rows (cons (list (strcat "KV" (itoa k)) (sd:rtos (/ (abs (sd:area pts)) 1e6) 2) (itoa nf) (itoa nc) (itoa ns)
                                       (sd:rtos (if (> (+ nf nc) 0) (/ (* 100.0 (- (* nc W H) cpa)) (* (+ nf nc) W H)) 0.0) 1) lbl)
                                 rows))
                (if nhan
                  (sd:text (sd:centroid pts) (strcat "KV" (itoa k) " - " (sd:rtos (/ (abs (sd:area pts)) 1e6) 2) " m2")
                           (* 3.0 sc) "MC" "SD-CHU"))
                (princ (strcat "\n  KV" (itoa k) ": " (sd:rtos (/ (abs (sd:area pts)) 1e6) 2) " m2, " (itoa nf) " nguyen, " (itoa nc) " cat"
                               (if (> ns 0) (strcat ", " (itoa ns) " cat hep < " (sd:num hep) " mm") "")
                               (if (/= lbl "") (strcat " [" lbl "]") ""))))))
          (setq *SD:NBRUN* nil)
          (princ (strcat "\n[SD] SDLOT: " (itoa (length rooms)) " khu vuc, " (itoa tf) " vien nguyen + " (itoa tc) " vien cat, hao hut "
                         (sd:rtos (if (> (+ tf tc) 0) (/ (* 100.0 twaste) (* (+ tf tc) W H)) 0.0) 1) "% (uoc tinh, chua tinh dung chung manh cat)."))
          (if (and rows (setq fn (sd:csv-name "_LotNhieuPhong.csv")) (setq f (sd:open fn "w")))
            (progn
              (write-line "sep=;" f)
              (write-line "Khu vuc;Dien tich (m2);Vien nguyen;Vien cat;Vien cat hep;Hao hut (%);Diem bat dau" f)
              (foreach r (reverse rows) (write-line (sd:join r ";") f))
              (princ (strcat "\n[SD] Da xuat: " (sd:close f)))))
          (if (and anh allnew) (sd:anhda allnew))
          (if van (c:SDVANDA)))
        (princ "\n[SD] Chua chon polyline."))))
  (setq *SD:NBRUN* nil *SD:GBATCH* nil)
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDTRUNGRON - Kiem tra luoi ron lien tuc xuyen cac phong: nhom vien lech luoi chinh bao nhieu mm, khoanh may, de xuat dich
;;; --------------------------------------------------------------------------
;; Dua v ve khoang [-p/2, p/2]
(defun sd:rg-fold (v p) (- v (* p (fix (+ (/ v p) (if (>= v 0.0) 0.5 -0.5))))))
;; items = ((ox oy tag) ...) -> cac nhom ((ox oy so-luong (tag ...)) ...), nhom dong nhat truoc
(defun sd:rg-classify (items tol / cls hit)
  (foreach it items
    (setq hit nil)
    (foreach c cls
      (if (and (null hit) (<= (abs (- (car it) (car c))) tol) (<= (abs (- (cadr it) (cadr c))) tol)) (setq hit c)))
    (if hit
      (setq cls (subst (list (car hit) (cadr hit) (1+ (caddr hit)) (cons (caddr it) (cadddr hit))) hit cls))
      (setq cls (cons (list (car it) (cadr it) 1 (list (caddr it))) cls))))
  (vl-sort cls '(lambda (a b) (> (caddr a) (caddr b)))))

(defun sd:rg-scan (ss jt tol sole / i e xd pts fr ang ang0 c0 w h w0 h0 items v ox oy px py nang nsz nin)
  (setq i 0 nang 0 nsz 0 nin 0 *SD:IFRAME* nil)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
    (if (and (>= (length xd) 12) (= (nth 1 xd) "F") (>= (length (setq pts (sd:curve-pts e))) 3))
      (progn
        (setq fr (sd:tile-frame pts) ang (car fr) w (cadr fr) h (caddr fr) nin (1+ nin))
        (if (null ang0) (setq ang0 ang w0 w h0 h c0 (cadddr fr) px (+ w0 jt) py (+ h0 jt)))
        (setq v (rem (- ang ang0) pi))
        (if (> v (/ pi 2.0)) (setq v (- v pi)))
        (if (< v (- (/ pi 2.0))) (setq v (+ v pi)))
        (cond ((< (abs v) 0.02))
              ((< (abs (- (abs v) (/ pi 2.0))) 0.02) (setq v w w h h v))
              (t (setq w nil)))
        (cond ((null w) (setq nang (1+ nang)))
              ((or (> (abs (- w w0)) 1.0) (> (abs (- h h0)) 1.0)) (setq nsz (1+ nsz)))
              (t (setq v (sd:rot (list (- (car (cadddr fr)) (car c0)) (- (cadr (cadddr fr)) (cadr c0))) (- ang0))
                       ox (if sole 0.0 (sd:rg-fold (car v) px)) oy (sd:rg-fold (cadr v) py)
                       items (cons (list ox oy e) items)))))))
  (list (if items (sd:rg-classify items tol)) nang nsz nin (length items) (if ang0 (+ w0 jt)) ))

(defun c:SDTRUNGRON (/ ss jt tol sole rs cls main nang nsz nin sc k boxes bx lay px)
  (sd:begin)
  (if (setq ss (sd:select-tiles "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn c\\U+1EA7n ki\\U+1EC3m tra l\\U+01B0\\U+1EDBi ron (Enter = t\\U+1EA5t c\\U+1EA3 trong b\\U+1EA3n v\\U+1EBD): "))
    (if (sd:dlg "Ki\\U+1EC3m tra l\\U+01B0\\U+1EDBi ron xuy\\U+00EAn c\\U+00E1c ph\\U+00F2ng (SDTRUNGRON)"
                (list (list "jt" "B\\U+1EC1 r\\U+1ED9ng ron (mm)" 'real0 (sd:cfg "RON-CU" 2.0))
                      (list "tol" "L\\U+1EC7ch cho ph\\U+00E9p gi\\U+1EEFa hai l\\U+01B0\\U+1EDBi (mm)" 'real (sd:cfg "RG-TOL" 2.0))
                      (list "kieu" "Ki\\U+1EC3u l\\U+00E1t" 'kw (sd:cfg "RG-KIEU" "Thang") '(("Thang" . "Th\\U+1EB3ng: ki\\U+1EC3m tra c\\U+1EA3 hai ph\\U+01B0\\U+01A1ng") ("Sole" . "So le: ch\\U+1EC9 ki\\U+1EC3m tra ph\\U+01B0\\U+01A1ng d\\U+1ECDc")))))
      (progn
        (setq jt (sd:cfg-put "RON-CU" (sd:v "jt")) tol (sd:cfg-put "RG-TOL" (sd:v "tol")) sole (= (sd:cfg-put "RG-KIEU" (sd:v "kieu")) "Sole")
              sc (sd:sc) rs (sd:rg-scan ss jt tol sole) cls (car rs) nang (cadr rs) nsz (caddr rs) nin (cadddr rs) px (nth 5 rs))
        (cond
          ((null cls) (princ "\n[SD] Kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn nguy\\U+00EAn (F) n\\U+00E0o \\U+0111\\U+1EC3 ki\\U+1EC3m tra."))
          (t
           (setq main (car cls) lay (sd:make-layer "SD-RON-LECH" 1 "Continuous" 25))
           (sd:cd-clear lay)
           (princ (strcat "\n[SD] SDTRUNGRON: " (itoa (nth 4 rs)) "/" (itoa nin) " vi\\U+00EAn nguy\\U+00EAn \\U+0111\\U+01B0\\U+1EE3c x\\U+00E9t; l\\U+01B0\\U+1EDBi ch\\U+00EDnh " (itoa (caddr main)) " vi\\U+00EAn, "
                          (itoa (length (cdr cls))) " nh\\U+00F3m l\\U+1EC7ch."))
           (if (> nang 0) (princ (strcat "\n  " (itoa nang) " vi\\U+00EAn kh\\U+00E1c h\\U+01B0\\U+1EDBng l\\U+01B0\\U+1EDBi (b\\U+1ECF qua).")))
           (if (> nsz 0) (princ (strcat "\n  " (itoa nsz) " vi\\U+00EAn kh\\U+00E1c kh\\U+1ED5 (b\\U+1ECF qua).")))
           (setq k 0)
           (foreach c (cdr cls)
             (setq k (1+ k) boxes nil)
             (foreach e (cadddr c) (setq boxes (cons (sd:cd-bbox (sd:curve-pts e)) boxes)))
             (princ (strcat "\n  Nh\\U+00F3m " (itoa k) ": " (itoa (caddr c)) " vi\\U+00EAn l\\U+1EC7ch (" (sd:rtos (- (car c) (car main)) 1) ", " (sd:rtos (- (cadr c) (cadr main)) 1)
                            ") mm so v\\U+1EDBi l\\U+01B0\\U+1EDBi ch\\U+00EDnh (tr\\U+1EE5c x theo h\\U+01B0\\U+1EDBng l\\U+01B0\\U+1EDBi); d\\U+1EDDi nh\\U+00F3m (" (sd:rtos (- (car main) (car c)) 1) ", " (sd:rtos (- (cadr main) (cadr c)) 1) ") mm \\U+0111\\U+1EC3 ron tr\\U+00F9ng."))
             (foreach bx (sd:cd-cluster boxes px)
               (sd:cd-cloud bx (* 3.0 sc) (* 8.0 sc) lay)
               (sd:text (list (car bx) (+ (cadddr bx) (* 6.0 sc))) (strcat "RON L\\U+1EC6CH (" (sd:rtos (- (car c) (car main)) 1) ", " (sd:rtos (- (cadr c) (cadr main)) 1) ") mm") (* 2.5 sc) "L" lay)))
           (if (null (cdr cls)) (princ "\n  L\\U+01B0\\U+1EDBi ron li\\U+00EAn t\\U+1EE5c, kh\\U+00F4ng c\\U+00F3 nh\\U+00F3m l\\U+1EC7ch."))))))
    (princ "\n[SD] Kh\\U+00F4ng t\\U+00ECm th\\U+1EA5y vi\\U+00EAn n\\U+00E0o (SDGACH / SDLOT)."))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDKIEMTONG - Luot kiem tong: ho so so lieu, vien hep / nho / thieu ma, ron khong deu, luoi ron lech, chuoi cao do; bao cao + CSV
;;; --------------------------------------------------------------------------
(defun c:SDKIEMTONG (/ ss tl i hep nho tolr tol jt tolg full fr ar mn nhep nnho nmat prs gaps med nbad rs cls nns n rows msgs m sc pt fn f sole)
  (sd:begin)
  (if (sd:dlg "L\\U+01B0\\U+1EE3t ki\\U+1EC3m t\\U+1ED5ng (SDKIEMTONG)"
              (list (list "hep" "Vi\\U+00EAn c\\U+1EAFt h\\U+1EB9p h\\U+01A1n (mm) b\\U+1ECB b\\U+00E1o" 'real (sd:cfg "KT-HEP" 50.0))
                    (list "nho" "Vi\\U+00EAn c\\U+1EAFt nh\\U+1ECF h\\U+01A1n (% vi\\U+00EAn nguy\\U+00EAn) b\\U+1ECB b\\U+00E1o" 'real (sd:cfg "KT-NHO" 15.0))
                    (list "tolr" "Ron l\\U+1EC7ch so v\\U+1EDBi ron ph\\U+1ED5 bi\\U+1EBFn qu\\U+00E1 (mm) b\\U+1ECB b\\U+00E1o" 'real (sd:cfg "KT-TOLR" 1.0))
                    (list "jt" "B\\U+1EC1 r\\U+1ED9ng ron (mm)" 'real0 (sd:cfg "RON-CU" 2.0))
                    (list "tolg" "L\\U+1EC7ch cho ph\\U+00E9p gi\\U+1EEFa hai l\\U+01B0\\U+1EDBi ron (mm)" 'real (sd:cfg "RG-TOL" 2.0))
                    (list "bang" "Ghi b\\U+00E1o c\\U+00E1o ra b\\U+1EA3n v\\U+1EBD" 'tog nil)))
    (progn
      (setq hep (sd:cfg-put "KT-HEP" (sd:v "hep")) nho (sd:cfg-put "KT-NHO" (sd:v "nho")) tolr (sd:cfg-put "KT-TOLR" (sd:v "tolr"))
            jt (sd:cfg-put "RON-CU" (sd:v "jt")) tolg (sd:cfg-put "RG-TOL" (sd:v "tolg")) sc (sd:sc) tol 15.0 *SD:IFRAME* nil
            sole (= (sd:cfg "RG-KIEU" "Thang") "Sole"))
      ;; 1. ho so so lieu
      (setq nns 0 n 0)
      (foreach k (sd:ho-keys) (setq n (1+ n)) (if (= (sd:ho-state (car k)) "NS") (setq nns (1+ nns))))
      (setq rows (cons (list "H\\U+1ED3 s\\U+01A1 s\\U+1ED1 li\\U+1EC7u (SDHOSO)" (strcat (itoa nns) "/" (itoa n) " s\\U+1ED1 ch\\U+01B0a x\\U+00E1c nh\\U+1EADn") (if (> nns 0) "CH\\U+01AFA X\\U+00C1C NH\\U+1EACN" "\\U+0110\\U+1EA0T")) rows))
      ;; 2 - 4. vien
      (if (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1) (-3 ("SD_TILE")))))
        (progn
          (setq i 0 nhep 0 nnho 0 nmat 0 nbad 0)
          (repeat (sslength ss) (setq tl (cons (sd:vn-rec (1+ i) (ssname ss i) nil) tl) i (1+ i)))
          (setq tl (reverse tl) full (sd:kt-full tl))
          (foreach r tl
            (setq fr (sd:tile-frame (nth 1 r)) mn (min (cadr fr) (caddr fr)) ar (abs (sd:area (nth 1 r))))
            (if (and (< mn hep) (or (null full) (< ar (* 0.98 full)))) (setq nhep (1+ nhep))
              (if (and full (< ar (* 0.01 nho full))) (setq nnho (1+ nnho)))))
          (setq rows (cons (list "Vi\\U+00EAn c\\U+1EAFt h\\U+1EB9p" (strcat (itoa nhep) " vi\\U+00EAn < " (sd:num hep) " mm") (if (> nhep 0) "C\\U+1EA2NH B\\U+00C1O" "\\U+0110\\U+1EA0T")) rows)
                rows (cons (list "Vi\\U+00EAn c\\U+1EAFt nh\\U+1ECF" (strcat (itoa nnho) " vi\\U+00EAn < " (sd:num nho) "% vi\\U+00EAn nguy\\U+00EAn") (if (> nnho 0) "C\\U+1EA2NH B\\U+00C1O" "\\U+0110\\U+1EA0T")) rows))
          (if (> (length tl) 1500)
            (setq rows (cons (list "Ron kh\\U+00F4ng \\U+0111\\U+1EC1u" (strcat (itoa (length tl)) " vi\\U+00EAn: qu\\U+00E1 nhi\\U+1EC1u, ch\\U+1EA1y SDKTLAT ri\\U+00EAng") "B\\U+1ECE QUA") rows))
            (progn
              (setq prs (sd:vn-pairs tl tol) gaps (sd:sort (mapcar 'caddr prs) '(lambda (a b) (< a b))))
              (if gaps (setq med (nth (/ (length gaps) 2) gaps)))
              (foreach pr prs (if (and med (> (abs (- (caddr pr) med)) tolr)) (setq nbad (1+ nbad))))
              (setq rows (cons (list "Ron kh\\U+00F4ng \\U+0111\\U+1EC1u" (strcat (itoa nbad) " m\\U+1ED1i n\\U+1ED1i l\\U+1EC7ch > " (sd:num tolr) " mm so v\\U+1EDBi ron ph\\U+1ED5 bi\\U+1EBFn " (if med (sd:rtos med 1) "-") " mm") (if (> nbad 0) "C\\U+1EA2NH B\\U+00C1O" "\\U+0110\\U+1EA0T")) rows))))
          (setq rs (sd:rg-scan ss jt tolg sole) cls (car rs))
          (setq rows (cons (list "L\\U+01B0\\U+1EDBi ron li\\U+00EAn t\\U+1EE5c" (cond ((null cls) "kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn nguy\\U+00EAn \\U+0111\\U+1EC3 x\\U+00E9t")
                                                           ((null (cdr cls)) (strcat (itoa (nth 4 rs)) " vi\\U+00EAn nguy\\U+00EAn c\\U+00F9ng m\\U+1ED9t l\\U+01B0\\U+1EDBi"))
                                                           (t (strcat (itoa (length (cdr cls))) " nh\\U+00F3m l\\U+1EC7ch l\\U+01B0\\U+1EDBi ch\\U+00EDnh (ch\\U+1EA1y SDTRUNGRON \\U+0111\\U+1EC3 khoanh)")))
                                 (cond ((null cls) "B\\U+1ECE QUA") ((cdr cls) "C\\U+1EA2NH B\\U+00C1O") (t "\\U+0110\\U+1EA0T"))) rows)))
        (setq rows (cons (list "Vi\\U+00EAn \\U+1ED1p l\\U+00E1t" "kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn n\\U+00E0o trong b\\U+1EA3n v\\U+1EBD" "B\\U+1ECE QUA") rows)))
      ;; 5. chuoi cao do
      (if (vlax-ldata-get "SD" "LC-M")
        (progn
          (setq msgs (sd:lc-check (sd:cfg "LC-M" 0.0) (sd:cfg "LC-BC" 20.0) (sd:cfg "LC-IW" 1.0) (sd:cfg "LC-ID" 1.5) (sd:cfg "HB-RL" -0.05) (sd:cfg "LC-DK" 0.0)))
          (setq rows (cons (list "Chu\\U+1ED7i cao \\U+0111\\U+1ED9 (SDLIENCAODO)" (if msgs (strcat (itoa (length msgs)) " c\\U+1EA3nh b\\U+00E1o (ch\\U+1EA1y SDLIENCAODO xem chi ti\\U+1EBFt)") "kh\\U+00F4ng c\\U+00F3 c\\U+1EA3nh b\\U+00E1o") (if msgs "C\\U+1EA2NH B\\U+00C1O" "\\U+0110\\U+1EA0T")) rows)))
        (setq rows (cons (list "Chu\\U+1ED7i cao \\U+0111\\U+1ED9 (SDLIENCAODO)" "ch\\U+01B0a nh\\U+1EADp s\\U+1ED1 li\\U+1EC7u" "B\\U+1ECE QUA") rows)))
      (setq rows (reverse rows) n 0)
      (foreach r rows (if (member (caddr r) '("C\\U+1EA2NH B\\U+00C1O" "CH\\U+01AFA X\\U+00C1C NH\\U+1EACN")) (setq n (1+ n))))
      (princ "\n[SD] SDKIEMTONG: b\\U+00E1o c\\U+00E1o ki\\U+1EC3m t\\U+1ED5ng")
      (foreach r rows (princ (strcat "\n  [" (caddr r) "] " (car r) ": " (cadr r))))
      (princ (strcat "\n  " (itoa n) "/" (itoa (length rows)) " m\\U+1EE5c c\\U+1EA7n x\\U+1EED l\\U+00FD tr\\U+01B0\\U+1EDBc khi ph\\U+00E1t h\\U+00E0nh. M\\U+1EE5c B\\U+1ECE QUA ngh\\U+0129a l\\U+00E0 ch\\U+01B0a ki\\U+1EC3m \\U+0111\\U+01B0\\U+1EE3c, kh\\U+00F4ng ph\\U+1EA3i \\U+0111\\U+1EA1t."))
      (if (and (sd:v "bang") (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+00E1o c\\U+00E1o (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil)))
        (sd:table2 pt "B\\U+00C1O C\\U+00C1O KI\\U+1EC2M TRA T\\U+1ED4NG" '(("M\\U+1EE4C KI\\U+1EC2M" 52) ("K\\U+1EBET QU\\U+1EA2" 80) ("TR\\U+1EA0NG TH\\U+00C1I" 30))
                   (mapcar '(lambda (r) (list "R" (list (car r) (cadr r) (caddr r)) nil)) rows) -1 sc))
      (if (and (setq fn (sd:csv-name "_KiemTong.csv")) (setq f (sd:open fn "w")))
        (progn
          (write-line "sep=;" f)
          (write-line "Muc kiem;Ket qua;Trang thai" f)
          (foreach r rows (write-line (sd:join r ";") f))
          (princ (strcat "\n[SD] \\U+0110\\U+00E3 xu\\U+1EA5t: " (sd:close f)))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDHOSO - Ho so so lieu du an: cac so dung chung cho nhieu lenh (ron, cao do, doc, du...), co trang thai da xac nhan / chua xac nhan
;;; --------------------------------------------------------------------------
;; (khoa nhan don-vi mac-dinh); khoa chinh la khoa nho cua tung lenh (sd:cfg)
(defun sd:ho-keys ()
  '(("RON-CU" "B\\U+1EC1 r\\U+1ED9ng ron" "mm" 2.0) ("LC-M" "Cao \\U+0111\\U+1ED9 s\\U+00E0n ch\\U+00EDnh ho\\U+00E0n thi\\U+1EC7n" "m" 0.0) ("LC-BC" "S\\U+00E0n WC h\\U+1EA1 so v\\U+1EDBi s\\U+00E0n ch\\U+00EDnh t\\U+1EA1i ng\\U+01B0\\U+1EE1ng c\\U+1EEDa" "mm" 20.0)
    ("LC-IW" "D\\U+1ED1c s\\U+00E0n WC v\\U+1EC1 ph\\U+1EC5u thu" "%" 1.0) ("LC-ID" "D\\U+1ED1c s\\U+00E2n h\\U+1ED3 v\\U+1EC1 ph\\U+1EC5u / r\\U+00E3nh thu" "%" 1.5) ("LC-DK" "Cao \\U+0111\\U+1ED9 s\\U+00E2n h\\U+1ED3 t\\U+1EA1i m\\U+00E9p h\\U+1ED3" "m" 0.0)
    ("HB-RL" "Cao \\U+0111\\U+1ED9 m\\U+1EF1c n\\U+01B0\\U+1EDBc h\\U+1ED3" "m" -0.05) ("HB-D1" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u n\\U+00F4ng" "mm" 1000.0) ("HB-D2" "\\U+0110\\U+1ED9 s\\U+00E2u n\\U+01B0\\U+1EDBc \\U+0111\\U+1EA7u s\\U+00E2u" "mm" 1500.0)
    ("BC-TD" "D\\U+00E0y \\U+0111\\U+00E1 \\U+0111\\U+1EE9ng t\\U+1EA1i ch\\U+1ED7 \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9" "mm" 20.0) ("BC-KL" "Keo ch\\U+1EEBa th\\U+00EAm t\\U+1EA1i ch\\U+1ED7 \\U+0111\\U+1ED5i cao \\U+0111\\U+1ED9" "mm" 10.0) ("CD-DU" "D\\U+01B0 m\\U+1EB7c \\U+0111\\U+1ECBnh c\\U+1EA1nh s\\U+00E1t t\\U+01B0\\U+1EDDng" "mm" 10.0)))
;; "XN" khi da xac nhan va gia tri khong doi tu luc xac nhan, nguoc lai "NS" (chua xac nhan: mac dinh, nhap tay chua duyet, hoac da doi sau khi duyet)
(defun sd:ho-state (k / rec cur)
  (setq rec (assoc k (sd:cfg "HOSO-ST" nil)) cur (vlax-ldata-get "SD" k))
  (if (and rec (= (cadr rec) "XN") (numberp cur) (numberp (caddr rec)) (< (abs (- cur (caddr rec))) 1e-6)) "XN" "NS"))
(defun sd:ho-warn (keys / bad)
  (foreach k keys (if (= (sd:ho-state k) "NS") (setq bad (cons (cadr (assoc k (sd:ho-keys))) bad))))
  (if bad (princ (strcat "\n[?] S\\U+1ED1 li\\U+1EC7u ch\\U+01B0a x\\U+00E1c nh\\U+1EADn trong h\\U+1ED3 s\\U+01A1 (SDHOSO): " (sd:join (reverse bad) "; ") "."))))

(defun c:SDHOSO (/ flds k st rows nns pt n)
  (sd:begin)
  (foreach k (sd:ho-keys)
    (setq flds (append flds (list (list (car k) (strcat (cadr k) " (" (caddr k) ")") 'real0 (sd:cfg (car k) (cadddr k)))
                                  (list (strcat "x" (car k)) "   \\U+0111\\U+00E3 x\\U+00E1c nh\\U+1EADn v\\U+1EDBi thi\\U+1EBFt k\\U+1EBF / hi\\U+1EC7n tr\\U+1EA1ng" 'tog (= (sd:ho-state (car k)) "XN"))))))
  ;; 27 muc de hai cot chia dung giua cac cap (so, xac nhan)
  (setq flds (append flds (list (list "bang" "Ghi b\\U+1EA3ng h\\U+1ED3 s\\U+01A1 s\\U+1ED1 li\\U+1EC7u ra b\\U+1EA3n v\\U+1EBD" 'tog nil)
                                (list "n1" "S\\U+1ED1 ch\\U+01B0a x\\U+00E1c nh\\U+1EADn l\\U+00E0 m\\U+1EB7c \\U+0111\\U+1ECBnh ho\\U+1EB7c n\\U+1ED9i suy: c\\U+00E1c l\\U+1EC7nh kh\\U+00E1c s\\U+1EBD c\\U+1EA3nh b\\U+00E1o." 'note)
                                (list "n2" "L\\U+1EC7nh kh\\U+00F4ng t\\U+1EF1 ki\\U+1EC3m ch\\U+1EE9ng s\\U+1ED1: b\\U+1EA1n ch\\U+1ECBu tr\\U+00E1ch nhi\\U+1EC7m khi t\\U+00EDch x\\U+00E1c nh\\U+1EADn." 'note))))
  (if (sd:dlg "H\\U+1ED3 s\\U+01A1 s\\U+1ED1 li\\U+1EC7u d\\U+1EF1 \\U+00E1n (SDHOSO): t\\U+00EDch \\U+0111\\U+00E3 x\\U+00E1c nh\\U+1EADn khi s\\U+1ED1 l\\U+1EA5y t\\U+1EEB thi\\U+1EBFt k\\U+1EBF ho\\U+1EB7c \\U+0111o hi\\U+1EC7n tr\\U+1EA1ng" flds)
    (progn
      (setq nns 0 n 0)
      (foreach k (sd:ho-keys)
        (sd:cfg-put (car k) (cond ((sd:v (car k))) ((cadddr k))))
        (setq st (if (sd:v (strcat "x" (car k))) "XN" "NS") n (1+ n))
        (if (= st "NS") (setq nns (1+ nns)))
        (setq rows (cons (list (car k) st (sd:cfg (car k) (cadddr k))) rows)))
      (sd:cfg-put "HOSO-ST" (reverse rows))
      (princ "\n[SD] SDHOSO: h\\U+1ED3 s\\U+01A1 s\\U+1ED1 li\\U+1EC7u d\\U+1EF1 \\U+00E1n")
      (foreach k (sd:ho-keys)
        (princ (strcat "\n  " (if (= (sd:ho-state (car k)) "XN") "[\\U+0111\\U+00E3 x\\U+00E1c nh\\U+1EADn]   " "[CH\\U+01AFA x\\U+00E1c nh\\U+1EADn] ") (cadr k) " = " (sd:num (sd:cfg (car k) (cadddr k))) " " (caddr k))))
      (princ (strcat "\n  " (itoa nns) "/" (itoa n) " s\\U+1ED1 li\\U+1EC7u ch\\U+01B0a x\\U+00E1c nh\\U+1EADn: s\\U+1ED1 ch\\U+01B0a x\\U+00E1c nh\\U+1EADn l\\U+00E0 m\\U+1EB7c \\U+0111\\U+1ECBnh ho\\U+1EB7c n\\U+1ED9i suy, kh\\U+00F4ng d\\U+00F9ng l\\U+00E0m s\\U+1ED1 cu\\U+1ED1i khi ph\\U+00E1t h\\U+00E0nh b\\U+1EA3n v\\U+1EBD."))
      (if (and (sd:v "bang") (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n b\\U+1EA3ng h\\U+1ED3 s\\U+01A1 s\\U+1ED1 li\\U+1EC7u (g\\U+00F3c tr\\U+00E1i tr\\U+00EAn) <b\\U+1ECF qua>: " nil)))
        (sd:table2 pt "H\\U+1ED2 S\\U+01A0 S\\U+1ED0 LI\\U+1EC6U D\\U+1EF0 \\U+00C1N"
                   '(("S\\U+1ED0 LI\\U+1EC6U" 62) ("GI\\U+00C1 TR\\U+1ECA" 22) ("\\U+0110\\U+01A0N V\\U+1ECA" 14) ("TR\\U+1EA0NG TH\\U+00C1I" 34))
                   (mapcar '(lambda (k) (list "R" (list (cadr k) (sd:num (sd:cfg (car k) (cadddr k))) (caddr k)
                                                         (if (= (sd:ho-state (car k)) "XN") "\\U+0110\\U+00C3 X\\U+00C1C NH\\U+1EACN" "CH\\U+01AFA X\\U+00C1C NH\\U+1EACN")) nil))
                           (sd:ho-keys))
                   -1 (sd:sc)))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDIMVIEN - Dim tu dong theo hang vien: chuoi tung vien (+ tong), ngang / dung, ngoai phong hoac xuyen trong phong
;;; --------------------------------------------------------------------------
;; Cac vien (khong tinh lo X) trong he luoi xoay ang0: ((xmin xmax ymin ymax) ...)
(defun sd:dv-tiles (ss ang0 / i e xd pts lp r)
  (setq i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
    (if (and (>= (length xd) 12) (/= (nth 1 xd) "X") (>= (length (setq pts (sd:curve-pts e))) 3))
      (progn
        (setq lp (mapcar '(lambda (p) (sd:rot (list (car p) (cadr p)) (- ang0))) pts))
        (setq r (cons (list (apply 'min (mapcar 'car lp)) (apply 'max (mapcar 'car lp))
                            (apply 'min (mapcar 'cadr lp)) (apply 'max (mapcar 'cadr lp)))
                      r)))))
  r)
;; Chuoi toa do ron / mep theo mot phuong: ia ib = chi so min / max doc theo phuong dim, ja jb = chi so phuong con lai, coord = duong cat
(defun sd:dv-chain (tl ia ib ja jb coord jt / row pts prev)
  (setq row (vl-remove-if-not '(lambda (r) (and (<= (nth ja r) coord) (>= (nth jb r) coord))) tl)
        row (vl-sort row '(lambda (a b) (< (nth ia a) (nth ia b)))))
  (if row
    (progn
      (setq pts (list (nth ia (car row))) prev (car row))
      (foreach r (cdr row)
        (if (<= (- (nth ia r) (nth ib prev)) (+ jt 1.5))
          (setq pts (cons (/ (+ (nth ia r) (nth ib prev)) 2.0) pts))
          (setq pts (cons (nth ia r) (cons (nth ib prev) pts))))
        (setq prev r))
      (reverse (cons (nth ib prev) pts)))))
;; Dim mot doan (hai diem toa do luoi p1 p2) theo truc ax ("X" / "Y" cua luoi), duong dim di qua diem luoi pd
(defun sd:dv-dim1 (p1 p2 ax ang0 pd / g1 g2 gd q n)
  (setq g1 (sd:rot p1 ang0) g2 (sd:rot p2 ang0) gd (sd:rot pd ang0)
        q (fix (+ 0.5 (/ ang0 (/ pi 2.0)))) n (abs (- ang0 (* q (/ pi 2.0)))))
  (if (< n 0.002)
    (sd:dim g1 g2 (if (= (= ax "X") (= (rem (abs q) 2) 0)) "H" "V") gd)
    (sd:dimal g1 g2 gd)))
;; Ve mot chuoi (+ tong neu hai hang); ax = "X" (dim ngang luoi) / "Y"; lc = toa do con lai cua duong dim; dir = +1 / -1 huong ra ngoai de dat dong tong
(defun sd:dv-draw (pts ax ang0 lc dir two off2 / a)
  (setq a pts)
  (while (cadr a)
    (sd:dv-dim1 (if (= ax "X") (list (car a) lc) (list lc (car a))) (if (= ax "X") (list (cadr a) lc) (list lc (cadr a))) ax ang0
                (if (= ax "X") (list (car a) lc) (list lc (car a))))
    (setq a (cdr a)))
  (if (and two (cadr pts))
    (sd:dv-dim1 (if (= ax "X") (list (car pts) lc) (list lc (car pts))) (if (= ax "X") (list (last pts) lc) (list lc (last pts))) ax ang0
                (if (= ax "X") (list (car pts) (+ lc (* dir off2))) (list (+ lc (* dir off2)) (car pts))))))

(defun c:SDDIMVIEN (/ ss tl sc fr ang0 huong hang vitri canh kc jt two xl yl xmin xmax ymin ymax pt lp h0 w0 ycand pts n nd)
  (sd:begin)
  (if (setq ss (sd:select-tiles "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn c\\U+1EE7a ph\\U+00F2ng c\\U+1EA7n dim (Enter = t\\U+1EA5t c\\U+1EA3 trong b\\U+1EA3n v\\U+1EBD): "))
    (if (sd:dlg "Dim t\\U+1EF1 \\U+0111\\U+1ED9ng theo h\\U+00E0ng vi\\U+00EAn (SDDIMVIEN)"
                (list (list "huong" "H\\U+01B0\\U+1EDBng dim" 'kw (sd:cfg "DV-HUONG" "Ca") '(("Ngang" . "Ngang theo l\\U+01B0\\U+1EDBi") ("Dung" . "\\U+0110\\U+1EE9ng theo l\\U+01B0\\U+1EDBi") ("Ca" . "C\\U+1EA3 hai")))
                      (list "hang" "S\\U+1ED1 h\\U+00E0ng dim" 'kw (sd:cfg "DV-HANG" "Hai") '(("Mot" . "M\\U+1ED9t h\\U+00E0ng: t\\U+1EEBng vi\\U+00EAn") ("Hai" . "Hai h\\U+00E0ng: t\\U+1EEBng vi\\U+00EAn + t\\U+1ED5ng")))
                      (list "vitri" "V\\U+1ECB tr\\U+00ED \\U+0111\\U+01B0\\U+1EDDng dim" 'kw (sd:cfg "DV-VITRI" "Ngoai") '(("Ngoai" . "Ngo\\U+00E0i ph\\U+00F2ng (h\\U+00E0ng vi\\U+00EAn s\\U+00E1t m\\U+00E9p)") ("Trong" . "Trong ph\\U+00F2ng (\\U+0111i qua \\U+0111i\\U+1EC3m ch\\U+1ECDn)")))
                      (list "canh" "Ph\\U+00EDa \\U+0111\\U+1EB7t dim ngo\\U+00E0i ph\\U+00F2ng" 'kw (sd:cfg "DV-CANH" "DT") '(("DT" . "D\\U+01B0\\U+1EDBi v\\U+00E0 tr\\U+00E1i") ("TP" . "Tr\\U+00EAn v\\U+00E0 ph\\U+1EA3i") ("Bon" . "C\\U+1EA3 b\\U+1ED1n ph\\U+00EDa")))
                      (list "kc" "Kho\\U+1EA3ng c\\U+00E1ch \\U+0111\\U+01B0\\U+1EDDng dim \\U+0111\\U+1EBFn m\\U+00E9p ph\\U+00F2ng (mm)" 'real (sd:cfg "DV-KC" (* 12.0 (sd:sc))))
                      (list "jt" "B\\U+1EC1 r\\U+1ED9ng ron (mm; ron nh\\U+1ECF h\\U+01A1n th\\U+00EC g\\U+1ED9p v\\U+00E0o b\\U+01B0\\U+1EDBc vi\\U+00EAn)" 'real0 (sd:cfg "RON-CU" 2.0))))
      (progn
        (setq huong (sd:cfg-put "DV-HUONG" (sd:v "huong")) hang (sd:cfg-put "DV-HANG" (sd:v "hang")) vitri (sd:cfg-put "DV-VITRI" (sd:v "vitri"))
              canh (sd:cfg-put "DV-CANH" (sd:v "canh")) kc (sd:cfg-put "DV-KC" (sd:v "kc")) jt (sd:cfg-put "RON-CU" (sd:v "jt"))
              two (= hang "Hai") sc (sd:sc) *SD:IFRAME* nil)
        ;; goc luoi = canh dai nhat cua vien dau tien
        (setq fr (sd:tile-frame (sd:curve-pts (ssname ss 0))) ang0 (car fr))
        (setq tl (sd:dv-tiles ss ang0))
        (if (null tl)
          (princ "\n[SD] Kh\\U+00F4ng c\\U+00F3 vi\\U+00EAn n\\U+00E0o \\U+0111\\U+1EC3 dim.")
          (progn
            (setq xmin (apply 'min (mapcar 'car tl)) xmax (apply 'max (mapcar 'cadr tl))
                  ymin (apply 'min (mapcar 'caddr tl)) ymax (apply 'max (mapcar 'cadddr tl))
                  h0 (- (cadddr (car tl)) (caddr (car tl))) w0 (- (cadr (car tl)) (car (car tl))) n 0)
            (sd:use-dimstyle sc)
            (if (= vitri "Trong")
              (if (setq pt (sd:getpt "\n\\U+0110i\\U+1EC3m n\\U+1EB1m tr\\U+00EAn h\\U+00E0ng / c\\U+1ED9t vi\\U+00EAn c\\U+1EA7n dim trong ph\\U+00F2ng: " nil))
                (progn
                  (setq pt (sd:rot (list (car pt) (cadr pt)) (- ang0)))
                  (if (member huong '("Ngang" "Ca"))
                    (if (setq pts (sd:dv-chain tl 0 1 2 3 (cadr pt) jt))
                      (progn (sd:dv-draw pts "X" ang0 (cadr pt) 1 two (* 8.0 sc)) (setq n (+ n (1- (length pts)))))))
                  (if (member huong '("Dung" "Ca"))
                    (if (setq pts (sd:dv-chain tl 2 3 0 1 (car pt) jt))
                      (progn (sd:dv-draw pts "Y" ang0 (car pt) 1 two (* 8.0 sc)) (setq n (+ n (1- (length pts)))))))))
              (progn
                ;; ngoai phong: lay hang / cot sat mep (thu vai vi tri cho den khi gap hang co vien)
                (foreach side (cond ((= canh "DT") '("D" "T")) ((= canh "TP") '("U" "P")) (t '("D" "U" "T" "P")))
                  (cond
                    ((and (member side '("D" "U")) (member huong '("Ngang" "Ca")))
                     (setq pts nil nd 0)
                     (while (and (null pts) (< nd 12))
                       (setq ycand (if (= side "D") (+ ymin (* nd 0.1 h0) 1.0) (- ymax (* nd 0.1 h0) 1.0))
                             pts (sd:dv-chain tl 0 1 2 3 ycand jt) nd (1+ nd)))
                     (if pts
                       (progn (sd:dv-draw pts "X" ang0 (if (= side "D") (- ymin kc) (+ ymax kc)) (if (= side "D") -1 1) two (* 8.0 sc))
                              (setq n (+ n (1- (length pts)))))))
                    ((and (member side '("T" "P")) (member huong '("Dung" "Ca")))
                     (setq pts nil nd 0)
                     (while (and (null pts) (< nd 12))
                       (setq xl (if (= side "T") (+ xmin (* nd 0.1 w0) 1.0) (- xmax (* nd 0.1 w0) 1.0))
                             pts (sd:dv-chain tl 2 3 0 1 xl jt) nd (1+ nd)))
                     (if pts
                       (progn (sd:dv-draw pts "Y" ang0 (if (= side "T") (- xmin kc) (+ xmax kc)) (if (= side "T") -1 1) two (* 8.0 sc))
                              (setq n (+ n (1- (length pts)))))))))))
            (princ (strcat "\n[SD] SDDIMVIEN: \\U+0111\\U+00E3 dim " (itoa n) " \\U+0111o\\U+1EA1n (layer SD-KICHTHUOC; b\\U+01B0\\U+1EDBc vi\\U+00EAn = vi\\U+00EAn + ron " (sd:rtos jt 1) " mm)."))
            (princ "\n  Dim ghi k\\U+00EDch th\\U+01B0\\U+1EDBc h\\U+00ECnh h\\U+1ECDc hi\\U+1EC7n c\\U+00F3 c\\U+1EE7a b\\U+1EA3n v\\U+1EBD: n\\U+1EBFu s\\U+1EEDa vi\\U+00EAn sau \\U+0111\\U+00F3 ph\\U+1EA3i dim l\\U+1EA1i.")))))
    (princ "\n[SD] Kh\\U+00F4ng t\\U+00ECm th\\U+1EA5y vi\\U+00EAn n\\U+00E0o (SDGACH / SDLOT)."))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDOPTUONG - Op tuong trung ron san: tuong trai phang theo canh, ron dung tuong trung ron san, kiem tra trung, hang tren cung
;;; --------------------------------------------------------------------------
;; Gom cac gia tri da sap thanh tam cum (gan nhau <= g)
(defun sd:ot-cluster (ts g / r cur)
  (foreach x ts
    (if (and cur (<= (- x (car cur)) g))
      (setq cur (cons x cur))
      (progn (if cur (setq r (cons (/ (apply '+ cur) (float (length cur))) r)))
             (setq cur (list x)))))
  (if cur (setq r (cons (/ (apply '+ cur) (float (length cur))) r)))
  (reverse r))
;; Cac ron san cat mat tuong p->q: toa do doc tuong (mm tu p) cua tam moi ron; tiles = ds da giac; near = khoang sat tuong
(defun sd:ot-fjoints (tiles p q near jt / len ux uy ts d tp)
  (setq len (distance p q) ux (/ (- (car q) (car p)) len) uy (/ (- (cadr q) (cadr p)) len))
  (foreach pts tiles
    (foreach v pts
      (setq d (abs (- (* (- (car v) (car p)) uy) (* (- (cadr v) (cadr p)) ux)))
            tp (+ (* (- (car v) (car p)) ux) (* (- (cadr v) (cadr p)) uy)))
      (if (and (<= d near) (> tp -1.0) (< tp (+ len 1.0))) (setq ts (cons tp ts)))))
  (sd:ot-cluster (vl-sort ts '<) (+ jt 2.0)))
;; Tam ron tuong doc theo 1 canh dai len: bat dau tu ron san j0 (nil = goc canh), buoc pw
(defun sd:ot-wjoints (j0 len pw jt / r x)
  (setq x (if j0 (- j0 (* pw (fix (+ 1.0 (/ j0 pw))))) (- (/ jt 2.0))))
  (while (< x (+ len pw))
    (setq r (cons x r) x (+ x pw)))
  (reverse r))

(defun c:SDOPTUONG (/ sc es e pts closed segs tl ssf i xd W H jt cao h0 near tol doors p1 p2 d1 d2 ep dacc p q len fa
                      fj wj j0 iv a b ca cb x0 x1 nf ncut area rows k y0 y1 ntot nmatch f dmin lay1 lay2 hcut j)
  (sd:begin)
  (setq sc (sd:sc))
  (setq es (entsel "\nCh\\U+1ECDn \\U+0111\\U+01B0\\U+1EDDng m\\U+1EB7t t\\U+01B0\\U+1EDDng (polyline, k\\U+00EDn ho\\U+1EB7c h\\U+1EDF): "))
  (if (not (and es (= (cdr (assoc 0 (entget (car es)))) "LWPOLYLINE")))
    (princ "\n[SD] C\\U+1EA7n ch\\U+1ECDn 1 polyline th\\U+1EC3 hi\\U+1EC7n m\\U+1EB7t t\\U+01B0\\U+1EDDng.")
    (if (sd:dlg "\\U+1ED0p t\\U+01B0\\U+1EDDng tr\\U+00F9ng ron s\\U+00E0n (SDOPTUONG)"
                (list (list "W" "Vi\\U+00EAn \\U+1ED1p: r\\U+1ED9ng d\\U+1ECDc t\\U+01B0\\U+1EDDng (mm)" 'real (sd:cfg "OT-W" 600.0))
                      (list "H" "Vi\\U+00EAn \\U+1ED1p: cao (mm)" 'real (sd:cfg "OT-H" 300.0))
                      (list "jt" "B\\U+1EC1 r\\U+1ED9ng ron (mm)" 'real0 (sd:cfg "RON-CU" 2.0))
                      (list "cao" "Chi\\U+1EC1u cao \\U+1ED1p t\\U+1EEB m\\U+1EB7t s\\U+00E0n ho\\U+00E0n thi\\U+1EC7n (mm)" 'real (sd:cfg "OT-CAO" 2400.0))
                      (list "h0" "\\U+1ED0p b\\U+1EAFt \\U+0111\\U+1EA7u cao h\\U+01A1n s\\U+00E0n (mm; ch\\U+1EEBa len ch\\U+00E2n t\\U+01B0\\U+1EDDng)" 'real0 (sd:cfg "OT-H0" 0.0))
                      (list "near" "Ron s\\U+00E0n t\\U+00EDnh khi vi\\U+00EAn s\\U+00E0n c\\U+00E1ch t\\U+01B0\\U+1EDDng kh\\U+00F4ng qu\\U+00E1 (mm)" 'real (sd:cfg "OT-NEAR" 60.0))
                      (list "tol" "Ron t\\U+01B0\\U+1EDDng coi l\\U+00E0 tr\\U+00F9ng ron s\\U+00E0n khi l\\U+1EC7ch kh\\U+00F4ng qu\\U+00E1 (mm)" 'real (sd:cfg "OT-TOL" 2.0))))
      (progn
        (setq W (sd:cfg-put "OT-W" (sd:v "W")) H (sd:cfg-put "OT-H" (sd:v "H")) jt (sd:cfg-put "RON-CU" (sd:v "jt"))
              cao (sd:cfg-put "OT-CAO" (sd:v "cao")) h0 (sd:cfg-put "OT-H0" (sd:v "h0"))
              near (sd:cfg-put "OT-NEAR" (sd:v "near")) tol (sd:cfg-put "OT-TOL" (sd:v "tol"))
              e (car es) closed (vlax-curve-isClosed e) pts (sd:curve-pts e) i 0)
        (sd:ho-warn '("RON-CU"))
        (princ "\nCh\\U+1ECDn c\\U+00E1c vi\\U+00EAn S\\U+00C0N c\\U+1EE7a ph\\U+00F2ng n\\U+00E0y \\U+0111\\U+1EC3 l\\U+1EA5y ron s\\U+00E0n (Enter = b\\U+1ECF qua, \\U+1ED1p b\\U+1EAFt \\U+0111\\U+1EA7u t\\U+1EEB g\\U+00F3c t\\U+01B0\\U+1EDDng): ")
        (if (setq ssf (ssget '((-3 ("SD_TILE")))))
          (repeat (sslength ssf)
            (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget (ssname ssf i) '("SD_TILE"))))) )
            (if (and (>= (length xd) 12) (/= (nth 1 xd) "X")) (setq tl (cons (sd:curve-pts (ssname ssf i)) tl)))
            (setq i (1+ i))))
        (while (and (setq p1 (sd:getpt "\n\\U+0110i\\U+1EC3m \\U+0111\\U+1EA7u l\\U+1ED7 c\\U+1EEDa tr\\U+00EAn \\U+0111\\U+01B0\\U+1EDDng t\\U+01B0\\U+1EDDng <Enter = h\\U+1EBFt>: " nil))
                    (setq p2 (sd:getpt "\n\\U+0110i\\U+1EC3m cu\\U+1ED1i l\\U+1ED7 c\\U+1EEDa: " p1)))
          (setq d1 (vlax-curve-getDistAtPoint e (vlax-curve-getClosestPointTo e p1))
                d2 (vlax-curve-getDistAtPoint e (vlax-curve-getClosestPointTo e p2))
                doors (cons (list (min d1 d2) (max d1 d2)) doors)))
        (setq doors (sd:sort doors '(lambda (x y) (< (car x) (car y))))
              segs (mapcar 'list pts (if closed (append (cdr pts) (list (car pts))) (cdr pts))))
        (if (setq ep (sd:getpt "\n\\U+0110i\\U+1EC3m ch\\U+00E8n m\\U+1EB7t \\U+0111\\U+1EE9ng \\U+1ED1p (\\U+0111\\U+1EA7u t\\U+01B0\\U+1EDDng, cao \\U+0111\\U+1ED9 s\\U+00E0n): " nil))
          (progn
            (sd:make-layer "SD-OP-TUONG" 7 "Continuous" 18)
            (setq lay1 (sd:make-layer "SD-OP-RON-TRUNG" 3 "Continuous" 18) lay2 (sd:make-layer "SD-OP-RON-LECH" 1 "Continuous" 25)
                  dacc 0.0 nf 0 ncut 0 area 0.0 ntot 0 nmatch 0 hcut nil)
            (foreach s segs
              (setq p (car s) q (cadr s) len (distance p q)
                    fj (if tl (sd:ot-fjoints tl p q near jt))
                    j0 (if fj (car fj))
                    wj (sd:ot-wjoints j0 len (+ W jt) jt))
              ;; cac doan lien tuc (tru lo cua) cua canh nay, toa do cuc bo
              (foreach iv (sd:subtract dacc (+ dacc len) doors)
                (setq a (- (car iv) dacc) b (- (cadr iv) dacc))
                (foreach j wj
                  (setq ca (max a (+ j (/ jt 2.0))) cb (min b (- (+ j (+ W jt)) (/ jt 2.0))))
                  (if (> (- cb ca) 1.0)
                    (progn
                      (setq k 0 y0 h0)
                      (while (< y0 (- cao 1.0))
                        (setq y1 (min (+ y0 H) cao))
                        (sd:rect (sd:p+ ep (+ dacc ca) y0) (- cb ca) (- y1 y0) "SD-OP-TUONG")
                        (if (and (equal (- cb ca) W 0.5) (equal (- y1 y0) H 0.5)) (setq nf (1+ nf)) (setq ncut (1+ ncut)))
                        (setq area (+ area (* (- cb ca) (- y1 y0))) y0 (+ y0 H jt) k (1+ k))
                        (if (and (>= y0 cao) (< (- y1 (- y0 H jt)) H)) (setq hcut (- y1 (- y0 H jt)))))))))
              ;; kiem tra trung ron: tung ron san trong doan nay
              (foreach f fj
                (if (and (> f 5.0) (< f (- len 5.0)))
                  (progn
                    (setq dmin (apply 'min (mapcar '(lambda (j) (abs (- f j))) wj)) ntot (1+ ntot))
                    (if (<= dmin tol)
                      (progn (setq nmatch (1+ nmatch))
                             (sd:line (sd:p+ ep (+ dacc f) (* -4.0 sc)) (sd:p+ ep (+ dacc f) (* -12.0 sc)) lay1))
                      (progn (sd:line (sd:p+ ep (+ dacc f) (* -4.0 sc)) (sd:p+ ep (+ dacc f) (* -12.0 sc)) lay2)
                             (sd:text (sd:p+ ep (+ dacc f) (* -14.0 sc)) (strcat "l\\U+1EC7ch " (sd:rtos dmin 1)) (* 2.0 sc) "MC" lay2))))))
              (setq dacc (+ dacc len)))
            (sd:line ep (sd:p+ ep dacc 0) "SD-OP-TUONG")
            (sd:text (sd:p+ ep 0 (+ cao (* 12.0 sc)))
                     (strcat "M\\U+1EB6T \\U+0110\\U+1EE8NG \\U+1ED0P T\\U+01AF\\U+1EDCNG " (sd:num W) "\\U+00D7" (sd:num H) ", ron " (sd:num jt) ", cao " (sd:num cao) ": " (itoa nf) " vi\\U+00EAn nguy\\U+00EAn, " (itoa ncut) " vi\\U+00EAn c\\U+1EAFt, " (sd:rtos (/ area 1e6) 2) " m\\U+00B2")
                     (* 3.0 sc) "L" "SD-CHU")
            (princ (strcat "\n[SD] SDOPTUONG: " (itoa nf) " vi\\U+00EAn nguy\\U+00EAn + " (itoa ncut) " vi\\U+00EAn c\\U+1EAFt, " (sd:rtos (/ area 1e6) 2) " m\\U+00B2."))
            (if tl
              (progn
                (princ (strcat "\n  Ron s\\U+00E0n c\\U+1EAFt t\\U+01B0\\U+1EDDng: " (itoa ntot) ", tr\\U+00F9ng ron t\\U+01B0\\U+1EDDng (l\\U+1EC7ch \\U+2264 " (sd:num tol) " mm): " (itoa nmatch)
                               (if (> ntot 0) (strcat " (" (sd:rtos (/ (* 100.0 nmatch) ntot) 0) "%)") "") "."))
                (if (and (> ntot 0) (< nmatch ntot))
                  (princ (strcat "\n  [!] " (itoa (- ntot nmatch)) " ron s\\U+00E0n kh\\U+00F4ng tr\\U+00F9ng ron t\\U+01B0\\U+1EDDng (v\\U+1EA1ch \\U+0111\\U+1ECF SD-OP-RON-LECH). Mu\\U+1ED1n tr\\U+00F9ng h\\U+1EBFt: r\\U+1ED9ng vi\\U+00EAn \\U+1ED1p + ron = b\\U+01B0\\U+1EDBc vi\\U+00EAn s\\U+00E0n d\\U+1ECDc t\\U+01B0\\U+1EDDng ho\\U+1EB7c \\U+01B0\\U+1EDBc s\\U+1ED1 c\\U+1EE7a n\\U+00F3, v\\U+00E0 \\U+0111\\U+1ED5i r\\U+1ED9ng vi\\U+00EAn \\U+1ED1p / ron cho kh\\U+1EDBp.")))
                (if (and (> ntot 0) (= nmatch ntot)) (princ "\n  Ron t\\U+01B0\\U+1EDDng tr\\U+00F9ng to\\U+00E0n b\\U+1ED9 ron s\\U+00E0n d\\U+1ECDc t\\U+01B0\\U+1EDDng.")))
              (princ "\n  Ch\\U+01B0a ch\\U+1ECDn vi\\U+00EAn s\\U+00E0n: ron t\\U+01B0\\U+1EDDng b\\U+1EAFt \\U+0111\\U+1EA7u t\\U+1EEB g\\U+00F3c t\\U+01B0\\U+1EDDng, ch\\U+01B0a ki\\U+1EC3m tra tr\\U+00F9ng ron s\\U+00E0n."))
            (if (and hcut (< hcut 50.0)) (princ (strcat "\n  [!] H\\U+00E0ng \\U+1ED1p tr\\U+00EAn c\\U+00F9ng ch\\U+1EC9 cao " (sd:rtos hcut 0) " mm: n\\U+00EAn \\U+0111\\U+1ED5i chi\\U+1EC1u cao \\U+1ED1p ho\\U+1EB7c \\U+0111i\\U+1EC3m b\\U+1EAFt \\U+0111\\U+1EA7u.")))
            (princ "\n  Ron \\U+0111\\U+1EE9ng t\\U+01B0\\U+1EDDng theo ron s\\U+00E0n d\\U+1ECDc t\\U+01B0\\U+1EDDng; ron ngang chia t\\U+1EEB m\\U+1EB7t s\\U+00E0n (ho\\U+1EB7c t\\U+1EEB cao \\U+0111\\U+1ED9 ch\\U+1EEBa len) l\\U+00EAn. L\\U+1ED7 c\\U+1EEDa ch\\U+1EC9 x\\U+00E9t theo chi\\U+1EC1u d\\U+1ECDc t\\U+01B0\\U+1EDDng, ch\\U+01B0a tr\\U+1EEB cao l\\U+1ED7 c\\U+1EEDa."))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDVAN - Kiem tra van da lien tuc giua cac vien ke nhau (dua vao vi tri cat tren tam do SDANHDA ghi lai)
;;;  SDKTLAT - Kiem tra ban ve lat: vien cat hep / nho, ron khong deu, vien chong nhau, o thieu ma vat lieu
;;; --------------------------------------------------------------------------
;; Hai da giac ke nhau: co 1 cap canh gan song song, cach <= tol, phan chong chieu dai >= 30. Tra ve khoang cach ron trung binh, hoac nil
(defun sd:vn-adj (pa pb tol / a1 b1 l ux uy d1 d2 t1 t2 ov r)
  (setq a1 (last pa))
  (foreach a2 pa
    (setq l (distance a1 a2) b1 (last pb))
    (if (> l 1e-6)
      (progn
        (setq ux (/ (- (car a2) (car a1)) l) uy (/ (- (cadr a2) (cadr a1)) l))
        (foreach b2 pb
          (if (null r)
            (progn
              (setq d1 (- (* (- (car b1) (car a1)) uy) (* (- (cadr b1) (cadr a1)) ux))
                    d2 (- (* (- (car b2) (car a1)) uy) (* (- (cadr b2) (cadr a1)) ux))
                    t1 (+ (* (- (car b1) (car a1)) ux) (* (- (cadr b1) (cadr a1)) uy))
                    t2 (+ (* (- (car b2) (car a1)) ux) (* (- (cadr b2) (cadr a1)) uy))
                    ov (- (min l (max t1 t2)) (max 0.0 (min t1 t2))))
              (if (and (<= (abs d1) tol) (<= (abs d2) tol) (>= ov 30.0))
                (setq r (/ (+ (abs d1) (abs d2)) 2.0)))))
          (setq b1 b2))))
    (setq a1 a2))
  r)

;; Ban ghi SDANHDA (id cx cy tam sx sy rong cao goc) ma tam do nam trong vien, nil neu khong co
(defun sd:vn-data (pts c r lk / res)
  (foreach x lk
    (if (and (null res) (<= (distance (list (cadr x) (caddr x)) c) (+ r 1.0))
             (sd:inpoly (list (cadr x) (caddr x)) pts))
      (setq res x)))
  res)

;; Ban ghi vien: (stt da-giac tam ban-kinh ename du-lieu-cat)
(defun sd:vn-rec (idx e lk / pts cx cy n r)
  (setq pts (sd:curve-pts e) n (float (length pts))
        cx (/ (apply '+ (mapcar 'car pts)) n) cy (/ (apply '+ (mapcar 'cadr pts)) n)
        r (apply 'max (mapcar '(lambda (q) (distance (list cx cy) q)) pts)))
  (list idx pts (list cx cy) r e (if lk (sd:vn-data pts (list cx cy) r lk))))

;; Cac cap vien ke nhau: ((a b ron) ...)
(defun sd:vn-pairs (tl tol / r rest a g)
  (setq rest tl)
  (while rest
    (setq a (car rest) rest (cdr rest))
    (foreach b rest
      (if (<= (distance (nth 2 a) (nth 2 b)) (+ (nth 3 a) (nth 3 b) tol))
        (if (setq g (sd:vn-adj (nth 1 a) (nth 1 b) tol))
          (setq r (cons (list a b g) r))))))
  r)

;; Hai vien ke nhau co cung 1 mieng van khong: (T lech) hoac (ly-do lech)
(defun sd:vn-cont (a b tolc / ca cb e dx dy ang d)
  (setq ca (nth 5 a) cb (nth 5 b))
  (cond
    ((or (null ca) (null cb) (null (nth 3 ca)) (null (nth 3 cb)) (null (nth 4 ca)) (null (nth 4 cb)))
     (list "khong co du lieu cat" 0.0))
    ((/= (nth 3 ca) (nth 3 cb)) (list "khac tam da" 0.0))
    ((> (abs (rem (- (nth 8 ca) (nth 8 cb)) (* 2.0 pi))) 0.02) (list "khac huong van" 0.0))
    (t
     (setq ang (nth 8 ca)
           e (sd:rot (list (- (car (nth 2 b)) (car (nth 2 a))) (- (cadr (nth 2 b)) (cadr (nth 2 a)))) (- ang))
           dx (- (+ (nth 4 cb) (/ (nth 6 cb) 2.0)) (+ (nth 4 ca) (/ (nth 6 ca) 2.0)))
           dy (- (+ (nth 5 cb) (/ (nth 7 cb) 2.0)) (+ (nth 5 ca) (/ (nth 7 ca) 2.0)))
           d (distance (list dx dy) e))
     (if (<= d tolc) (list t d) (list "lech vi tri tren tam" d)))))

;; Ghep van doi xung (bookmatch): hai vien ke nhau phai cat tu 2 tam LIEN TIEP (so tam hon kem 1),
;; cung huong va cung vi tri tren tam (lat guong khi lap). Tra ve (T lech) hoac (ly-do lech)
(defun sd:vn-book (a b tolc / ca cb d)
  (setq ca (nth 5 a) cb (nth 5 b))
  (cond
    ((or (null ca) (null cb) (null (nth 3 ca)) (null (nth 3 cb)) (null (nth 4 ca)) (null (nth 4 cb))
         (not (numberp (nth 3 ca))) (not (numberp (nth 3 cb))))
     (list "khong co du lieu cat" 0.0))
    ((/= (abs (- (nth 3 ca) (nth 3 cb))) 1) (list "khong phai 2 tam lien tiep (bookmatch)" 0.0))
    ((> (abs (rem (- (nth 8 ca) (nth 8 cb)) (* 2.0 pi))) 0.02) (list "khac huong van" 0.0))
    (t (setq d (distance (list (+ (nth 4 ca) (/ (nth 6 ca) 2.0)) (+ (nth 5 ca) (/ (nth 7 ca) 2.0)))
                         (list (+ (nth 4 cb) (/ (nth 6 cb) 2.0)) (+ (nth 5 cb) (/ (nth 7 cb) 2.0)))))
       (if (<= d tolc) (list t d) (list "lech vi tri doi xung tren tam" d)))))

(defun sd:vn-mid (a b) (list (/ (+ (car (nth 2 a)) (car (nth 2 b))) 2.0) (/ (+ (cadr (nth 2 a)) (cadr (nth 2 b))) 2.0)))

(defun c:SDVAN (/ ss tl i lk prs ok bad rs sc reasons fn f rows)
  (sd:begin)
  (setq *SD:IFRAME* nil)
  (if (not (setq lk (vlax-ldata-get "SD" "ANHDA")))
    (princ "\n[SD] Chua co du lieu cat tam: chay SDANHDA truoc (vi tri cat tung vien tren tam duoc ghi lai).")
    (if (sd:dlg "Kiem tra van da lien tuc (SDVAN)"
                (list (list "tol" "Khoang cach ron toi da giua 2 vien ke nhau (mm)" 'real (sd:cfg "VAN-TOL" 15.0))
                      (list "tolc" "Do lech cho phep giua vi tri tren ban ve va tren tam (mm)" 'real (sd:cfg "VAN-TOLC" 15.0))
                      (list "book" "Ghep van doi xung (bookmatch): 2 vien ke nhau cat tu 2 tam lien tiep, cung vi tri" 'tog nil)
                      (list "mark" "Khoanh do cac moi noi bi dut van (layer SD-KIEMTRA)" 'tog t)))
      (progn
        (sd:cfg-put "VAN-TOL" (sd:v "tol")) (sd:cfg-put "VAN-TOLC" (sd:v "tolc"))
        (princ "\nQuet chon cac polyline vien da: ")
        (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
          (progn
            (sd:make-layer "SD-KIEMTRA" 1 "Continuous" 35)
            (setq i 0 sc (sd:sc) ok 0 bad 0)
            (repeat (sslength ss) (setq tl (cons (sd:vn-rec (1+ i) (ssname ss i) lk) tl) i (1+ i)))
            (setq tl (reverse tl) prs (sd:vn-pairs tl (sd:v "tol")))
            (foreach pr prs
              (setq rs (if (sd:v "book") (sd:vn-book (car pr) (cadr pr) (sd:v "tolc")) (sd:vn-cont (car pr) (cadr pr) (sd:v "tolc"))))
              (if (eq (car rs) t)
                (setq ok (1+ ok))
                (progn
                  (setq bad (1+ bad) reasons (sd:addcnt (car rs) 1 reasons)
                        rows (cons (list (itoa (car (car pr))) (itoa (car (cadr pr))) (car rs) (sd:rtos (cadr rs) 0)) rows))
                  (if (sd:v "mark") (sd:lk-mark (sd:vn-mid (car pr) (cadr pr)) (* 2.0 sc) "" sc)))))
            (princ (strcat "\n[SD] SDVAN: " (itoa (length tl)) " vien, " (itoa (length prs)) " moi noi giua cac vien ke nhau: "
                           (itoa ok) " lien tuc van (" (sd:rtos (if prs (/ (* 100.0 ok) (length prs)) 0.0) 0) "%), " (itoa bad) " bi dut."))
            (foreach r reasons (princ (strcat "\n   " (car r) ": " (itoa (cdr r)) " moi noi")))
            (if (and rows (setq fn (sd:csv-name "_KiemTraVan.csv")) (setq f (sd:open fn "w")))
              (progn
                (write-line "sep=;" f)
                (write-line "Vien A;Vien B;Ly do;Lech (mm)" f)
                (foreach r (reverse rows) (write-line (sd:join r ";") f))
                (princ (strcat "\n[SD] Da xuat: " (sd:close f))))))
          (princ "\n[SD] Chua chon polyline.")))))
  (sd:finish))

;; Vien nguyen = hinh chu nhat xuat hien nhieu nhat (dai x rong lam tron); tra ve dien tich, nil neu khong co
(defun sd:kt-full (tl / g k e best)
  (foreach r tl
    (if (sd:dm-rect-p (nth 1 r))
      (progn
        (setq e (sd:tile-frame (nth 1 r))
              k (list (fix (+ 0.5 (max (cadr e) (caddr e)))) (fix (+ 0.5 (min (cadr e) (caddr e)))))
              g (sd:addcnt k 1 g)))))
  (foreach x g (if (or (null best) (> (cdr x) (cdr best))) (setq best x)))
  (if best (* (float (car (car best))) (cadr (car best)))))

(defun sd:kt-mat (r / xd)
  (if (setq xd (cdadr (assoc -3 (entget (nth 4 r) '("SD_TILE"))))) (cdr (car xd))))

(defun c:SDKTLAT (/ ss tl i hep nho tolr tol full fr ar mn rows prs gaps med nhep nnho ncho nbad nmat sc fn f ok med1 m g kgap bnd bo dmin nwall nchuyen)
  (sd:begin)
  (setq *SD:IFRAME* nil)
  (if (sd:dlg "Kiem tra ban ve lat (SDKTLAT)"
              (list (list "hep" "Vien cat hep hon (mm) bi bao" 'real (sd:cfg "KT-HEP" 50.0))
                    (list "nho" "Vien cat nho hon (% vien nguyen) bi bao" 'real (sd:cfg "KT-NHO" 15.0))
                    (list "tol" "Khoang cach ron toi da giua 2 vien ke nhau (mm)" 'real (sd:cfg "KT-TOL" 15.0))
                    (list "tolr" "Ron lech so voi ron pho bien qua (mm) bi bao" 'real (sd:cfg "KT-TOLR" 1.0))
                    (list "kgap" "Khe gian no chu vi toi thieu (mm): vien sat tuong ma cach tuong it hon bi bao, 0 = bo qua" 'real0 (sd:cfg "KT-KGAP" 0.0))
                    (list "mark" "Khoanh do cho co van de (layer SD-KIEMTRA)" 'tog t)))
    (progn
      (setq kgap (sd:cfg-put "KT-KGAP" (cond ((sd:v "kgap")) (0.0))))
      (setq hep (sd:cfg-put "KT-HEP" (sd:v "hep")) nho (sd:cfg-put "KT-NHO" (sd:v "nho")) tol (sd:cfg-put "KT-TOL" (sd:v "tol"))
            tolr (sd:cfg-put "KT-TOLR" (sd:v "tolr")) sc (sd:sc))
      (princ "\nQuet chon cac polyline vien da / gach: ")
      (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
        (progn
          (sd:make-layer "SD-KIEMTRA" 1 "Continuous" 35)
          (setq i 0 nhep 0 nnho 0 nbad 0 nmat 0 nwall 0 nchuyen 0)
          (if (> kgap 0.0)
            (if (setq bnd (entsel "\nChon polyline bien vung lat (de kiem khe gian no chu vi) <bo qua>: "))
              (setq bo (car bnd))))
          (repeat (sslength ss) (setq tl (cons (sd:vn-rec (1+ i) (ssname ss i) nil) tl) i (1+ i)))
          (setq tl (reverse tl) full (sd:kt-full tl))
          ;; tung vien: hep, nho, thieu ma vat lieu
          (foreach r tl
            (setq fr (sd:tile-frame (nth 1 r)) mn (min (cadr fr) (caddr fr)) ar (abs (sd:area (nth 1 r))))
            (if (not (cdadr (assoc -3 (entget (nth 4 r) '("SD_TILE"))))) (setq nmat (1+ nmat)))
            (if (and (< mn hep) (or (null full) (< ar (* 0.98 full))))
              (progn (setq nhep (1+ nhep) rows (cons (list (itoa (car r)) "vien cat hep" (sd:rtos mn 0)) rows))
                     (if (sd:v "mark") (sd:lk-mark (nth 2 r) (* 3.0 sc) "HEP" sc))))
            ;; khe gian no chu vi: dinh vien nao cach bien < kgap (tru sai so 0.5 mm) thi thieu khe
            (if (and bo (entget bo))
              (progn
                (setq dmin nil)
                (foreach q (nth 1 r)
                  (setq g (distance (list (car q) (cadr q) 0.0)
                                    (vlax-curve-getClosestPointTo bo (list (car q) (cadr q) 0.0))))
                  (if (or (null dmin) (< g dmin)) (setq dmin g)))
                (if (and dmin (< dmin (- kgap 0.5)))
                  (progn (setq nwall (1+ nwall) rows (cons (list (itoa (car r)) "thieu khe gian no sat tuong" (sd:rtos dmin 1)) rows))
                         (if (sd:v "mark") (sd:lk-mark (nth 2 r) (* 3.0 sc) "KHE" sc))))))
            (if (and full (< ar (* 0.01 nho full)) (not (and (< mn hep))))
              (progn (setq nnho (1+ nnho) rows (cons (list (itoa (car r)) "vien cat nho" (sd:rtos (/ ar 100.0) 0)) rows))
                     (if (sd:v "mark") (sd:lk-mark (nth 2 r) (* 3.0 sc) "NHO" sc)))))
          ;; ron khong deu: so voi ron trung vi
          (setq prs (sd:vn-pairs tl tol) gaps (sd:sort (mapcar 'caddr prs) '(lambda (a b) (< a b))))
          (if gaps (setq med (nth (/ (length gaps) 2) gaps)))
          (foreach pr prs
            (if (and med (> (abs (- (caddr pr) med)) tolr))
              (progn (setq nbad (1+ nbad) rows (cons (list (strcat (itoa (car (car pr))) "-" (itoa (car (cadr pr)))) "ron khong deu" (sd:rtos (caddr pr) 1)) rows))
                     (if (sd:v "mark") (sd:lk-mark (sd:vn-mid (car pr) (cadr pr)) (* 2.0 sc) "RON" sc)))))
          ;; chuyen tiep vat lieu: 2 vien ke nhau khac ma vat lieu, ron nho hon kgap -> can khe chuyen tiep
          (if (> kgap 0.0)
            (foreach pr prs
              (if (and (sd:kt-mat (car pr)) (sd:kt-mat (cadr pr))
                       (/= (sd:kt-mat (car pr)) (sd:kt-mat (cadr pr))) (< (caddr pr) (- kgap 0.5)))
                (progn (setq nchuyen (1+ nchuyen)
                             rows (cons (list (strcat (itoa (car (car pr))) "-" (itoa (car (cadr pr)))) "chuyen vat lieu thieu khe" (sd:rtos (caddr pr) 1)) rows))
                       (if (sd:v "mark") (sd:lk-mark (sd:vn-mid (car pr) (cadr pr)) (* 2.0 sc) "CHUYEN" sc))))))
          (princ (strcat "\n[SD] SDKTLAT: " (itoa (length tl)) " vien, " (itoa (length prs)) " moi noi."
                         (if (> kgap 0.0) (strcat "\n   Vien sat tuong thieu khe gian no < " (sd:num kgap) " mm: " (itoa nwall)
                                                  "\n   Cho chuyen vat lieu thieu khe: " (itoa nchuyen)) "")
                         (if full (strcat "\n   Vien nguyen: dien tich " (sd:rtos (/ full 1e6) 3) " m2/vien") "")
                         "\n   Vien cat hep < " (sd:num hep) " mm: " (itoa nhep)
                         "\n   Vien cat nho < " (sd:num nho) "% vien nguyen: " (itoa nnho)
                         "\n   Ron khong deu (pho bien " (if med (sd:rtos med 1) "-") " mm, lech > " (sd:num tolr) "): " (itoa nbad)
                         "\n   Vien chua co ma vat lieu (SD_TILE): " (itoa nmat)))
          (if (and rows (setq fn (sd:csv-name "_KiemTraLat.csv")) (setq f (sd:open fn "w")))
            (progn
              (write-line "sep=;" f)
              (write-line "Vien;Van de;Gia tri (mm hoac cm2)" f)
              (foreach r (reverse rows) (write-line (sd:join r ";") f))
              (princ (strcat "\n[SD] Da xuat: " (sd:close f))))))
        (princ "\n[SD] Chua chon polyline."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDIEMBD - So sanh cac diem bat dau rai luoi vien: vien cat, vien cat hep, hao hut, goi y diem tot nhat
;;; --------------------------------------------------------------------------
;; Giao da giac pts (co the lom) voi hinh chu nhat [x0 x1] x [y0 y1]: da giac giao (co the suy bien nhung dien tich dung) hoac nil
(defun sd:cl-rect (pts x0 y0 x1 y1 / r)
  (setq r (sd:clipx pts x0 t))
  (if r (setq r (sd:clipx r x1 nil)))
  (if r (setq r (mapcar 'reverse r)))
  (if r (setq r (sd:clipx r y0 t)))
  (if r (setq r (sd:clipx r y1 nil)))
  (if r (mapcar 'reverse r)))

(defun sd:cl-area (pts) (if (and pts (> (length pts) 2)) (abs (sd:area pts)) 0.0))

;; Danh gia luoi vien W x H, ron jt, goc vien trai-duoi tai (ox oy) tren vung rp (tru cac lo holes), toa do da xoay theo luoi.
;; Tra ve (so-vien-nguyen so-vien-cat so-vien-cat-hep canh-hep-nhat hao-hut% )
(defun sd:od-eval (rp holes W H jt ox oy hep / bb x0 y0 x1 y1 px py i j i1 j1 tx ty c a nf nc ns mn cut full bw bh xs ys)
  (setq bb (sd:bbox rp) x0 (car (car bb)) y0 (cadr (car bb)) x1 (car (cadr bb)) y1 (cadr (cadr bb))
        px (+ W jt) py (+ H jt) full (* W H) nf 0 nc 0 ns 0 cut 0.0 mn 1e9
        i (fix (- (/ (- x0 ox) px) 1.0)) i1 (fix (+ (/ (- x1 ox) px) 1.0))
        j1 (fix (+ (/ (- y1 oy) py) 1.0)))
  (while (<= i i1)
    (setq j (fix (- (/ (- y0 oy) py) 1.0)))
    (while (<= j j1)
      (setq tx (+ ox (* i px)) ty (+ oy (* j py)))
      (if (and (< tx x1) (> (+ tx W) x0) (< ty y1) (> (+ ty H) y0))
        (progn
          (setq c (sd:cl-rect rp tx ty (+ tx W) (+ ty H)) a (sd:cl-area c))
          (foreach ho holes (if (> a 1.0) (setq a (- a (sd:cl-area (sd:cl-rect ho tx ty (+ tx W) (+ ty H)))))))
          (if (> a 1.0)
            (if (>= a (* 0.999 full))
              (setq nf (1+ nf))
              (progn
                (setq nc (1+ nc) cut (+ cut a)
                      xs (mapcar 'car c) ys (mapcar 'cadr c)
                      bw (- (apply 'max xs) (apply 'min xs)) bh (- (apply 'max ys) (apply 'min ys)))
                (setq mn (min mn bw bh))
                (if (< (min bw bh) hep) (setq ns (1+ ns))))))))
      (setq j (1+ j)))
    (setq i (1+ i)))
  (list nf nc ns (if (< mn 1e9) mn 0.0)
        (if (> (+ nf nc) 0) (/ (* 100.0 (- (* nc full) cut)) (* (+ nf nc) full)) 0.0)))

;; Cac diem bat dau ung vien (ten ox oy) trong he luoi da xoay; q = 1 them luoi thu mat 5 x 5 trong 1 chu ky
(defun sd:od-cands (rp W H jt q / bb x0 y0 x1 y1 cx cy px py r k m)
  (setq bb (sd:bbox rp) x0 (car (car bb)) y0 (cadr (car bb)) x1 (car (cadr bb)) y1 (cadr (cadr bb))
        cx (/ (+ x0 x1) 2.0) cy (/ (+ y0 y1) 2.0) px (+ W jt) py (+ H jt)
        r (list (list "Goc trai-duoi" x0 y0) (list "Goc phai-duoi" (- x1 W) y0)
                (list "Goc trai-tren" x0 (- y1 H)) (list "Goc phai-tren" (- x1 W) (- y1 H))
                (list "Tam vien o tam" (- cx (/ W 2.0)) (- cy (/ H 2.0)))
                (list "Mach o tam" (+ cx (/ jt 2.0)) (+ cy (/ jt 2.0)))))
  (if (and q (> q 0))
    (progn
      (setq k 0)
      (while (< k 5)
        (setq m 0)
        (while (< m 5)
          (setq r (append r (list (list (strcat "Luoi " (itoa k) "," (itoa m)) (+ x0 (* k (/ px 5.0))) (+ y0 (* m (/ py 5.0)))))))
          (setq m (1+ m)))
        (setq k (1+ k)))))
  r)

(defun sd:od-less (a b)
  (cond ((/= (nth 2 (cadr a)) (nth 2 (cadr b))) (< (nth 2 (cadr a)) (nth 2 (cadr b))))
        ((/= (nth 1 (cadr a)) (nth 1 (cadr b))) (< (nth 1 (cadr a)) (nth 1 (cadr b))))
        (t (< (nth 4 (cadr a)) (nth 4 (cadr b))))))

(defun c:SDDIEMBD (/ r e pts hs holes i W H jt hep q huong ang rp rh cands res best sc ow k kgap o)
  (sd:begin)
  (setq *SD:IFRAME* nil)
  (if (sd:dlg "So sanh diem bat dau rai (SDDIEMBD)"
              (list (list "W" "Vien - dai (mm)" 'real (sd:cfg "DB-W" 600.0))
                    (list "H" "Vien - rong (mm)" 'real (sd:cfg "DB-H" 600.0))
                    (list "jt" "Ron (mm)" 'real0 (sd:cfg "DB-JT" 2.0))
                    (list "huong" "Huong luoi" 'kw (sd:cfg "DB-HUONG" "Truc")
                          '(("Truc" . "Theo truc X, Y") ("Canh" . "Theo canh dai nhat cua vung") ("Goc" . "Nhap goc (do)")))
                    (list "ang" "Goc luoi (do)" 'real0 (sd:cfg "DB-ANG" 0.0) nil '("huong" "Goc"))
                    (list "hep" "Vien cat hep hon (mm) tinh la vun" 'real (sd:cfg "DB-HEP" 50.0))
                    (list "q" "Do ky" 'kw (sd:cfg "DB-Q" "Nhanh")
                          '(("Nhanh" . "Nhanh: 6 diem (4 goc, 2 tam)") ("Ky" . "Ky: them 25 diem quet trong 1 chu ky luoi")))
                    (list "kg" "Khe sat tuong (mm): vung lat lui vao tu bien, lo/cot no ra (0 = khong)" 'real0 (sd:cfg "DB-KG" 0.0))
                    (list "ve" "Danh dau diem tot nhat tren ban ve" 'tog t)))
    (progn
      (setq kgap (sd:cfg-put "DB-KG" (cond ((sd:v "kg")) (0.0))))
      (setq W (sd:cfg-put "DB-W" (sd:v "W")) H (sd:cfg-put "DB-H" (sd:v "H")) jt (sd:cfg-put "DB-JT" (sd:v "jt"))
            huong (sd:cfg-put "DB-HUONG" (sd:v "huong")) hep (sd:cfg-put "DB-HEP" (sd:v "hep")) q (sd:cfg-put "DB-Q" (sd:v "q"))
            ang (sd:cfg-put "DB-ANG" (cond ((sd:v "ang")) (0.0))) sc (sd:sc))
      (if (setq r (entsel "\nChon polyline kin la bien vung lat: "))
        (if (and (= (cdr (assoc 0 (entget (car r)))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget (car r)))))))
          (progn
            (setq e (car r) pts (sd:curve-pts e))
            ;; khe sat tuong: lui bien vao kgap
            (if (> kgap 0.0)
              (if (setq o (sd:offset e kgap t))
                (setq pts (sd:curve-pts o))
                (princ "\n[SD] Khong lui vao duoc khe sat tuong, tinh theo bien goc.")))
            (princ "\nChon cac polyline kin la lo / cot trong vung <Enter = khong co>: ")
            (if (setq hs (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
              (progn (setq i 0)
                     (repeat (sslength hs)
                       (if (not (equal (ssname hs i) e))
                         (setq holes (cons (sd:curve-pts (cond ((and (> kgap 0.0) (sd:offset (ssname hs i) kgap nil))) ((ssname hs i)))) holes)))
                       (setq i (1+ i)))))
            ;; goc luoi (rad)
            (setq ang (cond ((= huong "Truc") 0.0)
                            ((= huong "Canh")
                             (setq ow (last pts) k nil)
                             (foreach b pts (if (or (null k) (> (distance ow b) (car k))) (setq k (list (distance ow b) (angle ow b)))) (setq ow b))
                             (cadr k))
                            (t (* pi (/ ang 180.0))))
                  rp (mapcar '(lambda (p) (sd:rot p (- ang))) pts)
                  rh (mapcar '(lambda (hp) (mapcar '(lambda (p) (sd:rot p (- ang))) hp)) holes)
                  cands (sd:od-cands rp W H jt (if (= q "Ky") 1 0)))
            (princ (strcat "\n[SD] Dang danh gia " (itoa (length cands)) " diem bat dau, luoi " (sd:num W) " x " (sd:num H)
                           ", goc " (sd:rtos (* 180.0 (/ ang pi)) 1) " do ..."))
            (foreach c cands
              (setq res (cons (list c (sd:od-eval rp rh W H jt (cadr c) (caddr c) hep)) res)))
            (setq res (sd:sort res 'sd:od-less))
            (princ "\n   Diem bat dau (luoi)          Nguyen  Cat  Cat-hep  Canh-hep-nhat  Hao-hut")
            (setq k 0)
            (foreach x res
              (if (< k 8)
                (princ (strcat "\n " (if (= k 0) "> " "  ") (car (car x)) "   " (itoa (car (cadr x))) "   " (itoa (cadr (cadr x))) "   "
                               (itoa (caddr (cadr x))) "   " (sd:rtos (cadddr (cadr x)) 0) " mm   " (sd:rtos (nth 4 (cadr x)) 1) "%")))
              (setq k (1+ k)))
            (setq best (car res) ow (sd:rot (list (cadr (car best)) (caddr (car best))) ang))
            (princ (strcat "\n[SD] Tot nhat: " (car (car best)) ", goc vien trai-duoi cua luoi tai ("
                           (sd:rtos (car ow) 0) ", " (sd:rtos (cadr ow) 0) "), goc " (sd:rtos (* 180.0 (/ ang pi)) 1)
                           " do: " (itoa (cadr (cadr best))) " vien cat, " (itoa (caddr (cadr best))) " vien cat hep. Dung diem nay lam diem bat dau trong SDRAITAM / SDGACH."))
            (if (sd:v "ve")
              (progn
                (sd:make-layer "SD-DIEMBD" 3 "Continuous" 25)
                (entmake (list '(0 . "CIRCLE") '(8 . "SD-DIEMBD") (cons 10 (list (car ow) (cadr ow) 0.0)) (cons 40 (* 3.0 sc))))
                (sd:text (sd:p+ ow 0 (* 5.0 sc)) (strcat "DIEM BAT DAU: " (car (car best))) (* 2.5 sc) "L" "SD-DIEMBD"))))
          (princ "\n[SD] Can chon polyline kin."))
        (princ "\n[SD] Chua chon."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDKHEGIAN - Khe co gian: khe chu vi sat tuong + khe phan vung vung lat (doan lien tuc dai nhat)
;;;  SDTHOATNUOC - Diem thoat nuoc + doc san: chenh cao den cac goc, khoanh vung vien cat quanh pheu thu
;;; --------------------------------------------------------------------------
;; Khoang cach nho nhat tu diem p den cac pheu drs
(defun sd:dr-near (p drs / d)
  (foreach q drs (if (or (null d) (< (distance p q) d)) (setq d (distance p q))))
  d)

;; Pheu gan p nhat
(defun sd:dr-nearpt (p drs / b)
  (foreach q drs (if (or (null b) (< (distance p q) (distance p b))) (setq b q)))
  b)

;; Diem xa pheu nhat trong vung pts (dinh va luoi lay mau): (khoang-cach diem)
(defun sd:dr-far (pts drs step / bb x y best d ys)
  (foreach p pts
    (setq d (sd:dr-near p drs))
    (if (or (null best) (> d (car best))) (setq best (list d p))))
  (setq bb (sd:bbox pts) x (car (car bb)))
  (while (<= x (car (cadr bb)))
    (setq y (cadr (car bb)))
    (while (<= y (cadr (cadr bb)))
      (if (sd:inpoly (list x y) pts)
        (progn (setq d (sd:dr-near (list x y) drs))
               (if (> d (car best)) (setq best (list d (list x y))))))
      (setq y (+ y step)))
    (setq x (+ x step)))
  best)

;; Vi tri cac khe phan vung doc theo khoang a..b chia deu thanh cac khoang <= mx, cham vao tam mach neu co luoi vien (w + jt)
(defun sd:kg-pos (a b mx per / n i r x)
  (setq n (max 1 (fix (+ (/ (- b a) mx) 0.999999))) i 1)
  (while (< i n)
    (setq x (+ a (* i (/ (- b a) n))))
    (if (and per (> per 1.0)) (setq x (+ a (* per (fix (+ 0.5 (/ (- x a) per)))))))
    (if (and (> x (+ a 1.0)) (< x (- b 1.0)) (not (member x r))) (setq r (cons x r)))
    (setq i (1+ i)))
  (reverse r))

(defun c:SDKHEGIAN (/ r e pts hs holes i kg mx ge W jt per bb x0 y0 x1 y1 xs ys n tot o x y sg)
  (sd:begin)
  (if (sd:dlg "Khe co gian (SDKHEGIAN)"
              (list (list "kg" "Khe sat tuong - chua cach tuong (mm, 0 = khong ve)" 'real0 (sd:cfg "KG-KG" 10.0))
                    (list "mx" "Khoang cach toi da giua cac khe phan vung (mm, 0 = khong chia)" 'real0 (sd:cfg "KG-MX" 6000.0))
                    (list "ge" "Be rong khe phan vung (mm)" 'real (sd:cfg "KG-GE" 10.0))
                    (list "W" "Luoi vien de can khe vao giua ron - rong vien (mm, 0 = khong can)" 'real0 (sd:cfg "KG-W" 0.0))
                    (list "jt" "Ron (mm)" 'real0 (sd:cfg "KG-JT" 2.0))))
    (progn
      (setq kg (sd:cfg-put "KG-KG" (sd:v "kg")) mx (sd:cfg-put "KG-MX" (sd:v "mx")) ge (sd:cfg-put "KG-GE" (sd:v "ge"))
            W (sd:cfg-put "KG-W" (sd:v "W")) jt (sd:cfg-put "KG-JT" (sd:v "jt")) per (if (> W 0.0) (+ W jt)))
      (if (setq r (entsel "\nChon polyline kin la bien vung lat: "))
        (if (and (= (cdr (assoc 0 (entget (car r)))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget (car r)))))))
          (progn
            (setq e (car r) pts (sd:curve-pts e))
            (princ "\nChon cac polyline kin la lo / cot <Enter = khong co>: ")
            (if (setq hs (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
              (progn (setq i 0)
                     (repeat (sslength hs)
                       (if (not (equal (ssname hs i) e)) (setq holes (cons (sd:curve-pts (ssname hs i)) holes)))
                       (setq i (1+ i)))))
            (sd:make-layer "SD-KHE" 6 "Continuous" 35)
            (setq tot 0.0 n 0)
            ;; khe sat tuong: bao ngoai lui vao kg
            (if (> kg 0.0)
              (if (setq o (sd:offset e kg t))
                (progn (sd:pline (sd:curve-pts o) t "SD-KHE") (setq n (1+ n) tot (+ tot (vla-get-Length (vlax-ename->vla-object o)))))
                (princ "\n[SD] Khong lui vao duoc khe sat tuong (bien qua nho hay lom).")))
            ;; khe phan vung
            (if (> mx 0.0)
              (progn
                (setq bb (sd:bbox pts) x0 (car (car bb)) y0 (cadr (car bb)) x1 (car (cadr bb)) y1 (cadr (cadr bb))
                      xs (sd:kg-pos x0 x1 mx per) ys (sd:kg-pos y0 y1 mx per))
                (foreach x xs
                  (foreach sg (sd:clip-segh (list x y0) (list x y1) pts holes)
                    (sd:plinew sg nil ge "SD-KHE") (setq n (1+ n) tot (+ tot (distance (car sg) (cadr sg))))))
                (foreach y ys
                  (foreach sg (sd:clip-segh (list x0 y) (list x1 y) pts holes)
                    (sd:plinew sg nil ge "SD-KHE") (setq n (1+ n) tot (+ tot (distance (car sg) (cadr sg))))))))
            (princ (strcat "\n[SD] SDKHEGIAN: " (itoa n) " khe, tong chieu dai " (sd:rtos (/ tot 1000.0) 2) " m"
                           (if (> mx 0.0) (strcat " (phan vung moi " (itoa (1+ (length xs))) " x " (itoa (1+ (length ys))) " o, khoang <= " (sd:num mx) ")") "") ".")))
          (princ "\n[SD] Can chon polyline kin."))
        (princ "\n[SD] Chua chon."))))
  (sd:finish))

(defun c:SDTHOATNUOC (/ r e pts drs p it rad hmax far h sc step i d)
  (sd:begin)
  (if (sd:dlg "Thoat nuoc va doc san (SDTHOATNUOC)"
              (list (list "it" "Doc san (%)" 'real (sd:cfg "TN-I" 1.0))
                    (list "rad" "Ban kinh khoanh vien cat quanh pheu thu (mm)" 'real0 (sd:cfg "TN-R" 300.0))
                    (list "hmax" "Chenh cao toi da cho phep (mm, vua lat)" 'real (sd:cfg "TN-HMAX" 30.0))))
    (progn
      (setq it (sd:cfg-put "TN-I" (sd:v "it")) rad (sd:cfg-put "TN-R" (sd:v "rad")) hmax (sd:cfg-put "TN-HMAX" (sd:v "hmax")) sc (sd:sc))
      (if (setq r (entsel "\nChon polyline kin la bien vung lat: "))
        (if (and (= (cdr (assoc 0 (entget (car r)))) "LWPOLYLINE") (= 1 (logand 1 (cdr (assoc 70 (entget (car r)))))))
          (progn
            (setq e (car r) pts (sd:curve-pts e))
            (while (setq p (getpoint "\nChon vi tri pheu thu nuoc <Enter xong>: "))
              (setq drs (cons (sd:2d p) drs)))
            (if (null drs)
              (princ "\n[SD] Chua chon pheu thu nuoc.")
              (progn
                (setq step (max 100.0 (/ (distance (car (sd:bbox pts)) (cadr (sd:bbox pts))) 40.0))
                      far (sd:dr-far pts drs step) h (* (car far) (/ it 100.0)))
                (sd:make-layer "SD-THOATNUOC" 4 "Continuous" 25)
                (foreach p drs
                  (entmake (list '(0 . "CIRCLE") '(8 . "SD-THOATNUOC") (cons 10 (list (car p) (cadr p) 0.0)) (cons 40 (* 1.5 sc))))
                  (if (> rad 0.0) (entmake (list '(0 . "CIRCLE") '(8 . "SD-THOATNUOC") (cons 10 (list (car p) (cadr p) 0.0)) (cons 40 rad))))
                  (sd:text (sd:p+ p 0 (+ rad (* 3.0 sc))) (strcat "PHEU THU, i = " (sd:num it) "%") (* 2.5 sc) "L" "SD-THOATNUOC"))
                ;; nhan do cao tai cac dinh bien, so voi mieng pheu
                (foreach q pts
                  (setq d (sd:dr-near q drs))
                  (sd:text (sd:p+ q 0 (* 2.0 sc)) (strcat "+" (sd:rtos (* d (/ it 100.0)) 0)) (* 2.0 sc) "L" "SD-THOATNUOC"))
                (sd:line (cadr far) (sd:dr-nearpt (cadr far) drs) "SD-THOATNUOC")
                (princ (strcat "\n[SD] SDTHOATNUOC: " (itoa (length drs)) " pheu thu; diem xa nhat cach pheu " (sd:rtos (/ (car far) 1000.0) 2)
                               " m, chenh cao " (sd:rtos h 1) " mm voi doc " (sd:num it) "%."))
                (if (or (< it 1.0) (> it 2.0))
                  (princ "\n[?] D\\U+1ED1c ngo\\U+00E0i 1 - 2%: TCVN 4260:2012 \\U+00A76.2.24 l\\U+1EA5y d\\U+1ED1c s\\U+00E2n quanh b\\U+1EC3 1 - 2% v\\U+1EC1 ph\\U+00EDa ph\\U+1EC5u thu (\\U+0111\\U+00E1y b\\U+1EC3 d\\U+1ED1c v\\U+1EC1 h\\U+1ED1 thu 1 - 3%, \\U+00A75.1.11)."))
                (if (> h hmax)
                  (princ (strcat "\n[!] Vuot " (sd:num hmax) " mm cho phep: them pheu thu hoac giam doc / tang lop vua. Chenh cao nay lam viec cat vien theo doc va mach khong con thang hang.")))
                (if (> rad 0.0) (princ (strcat "\n   Vong tron ban kinh " (sd:num rad) " mm quanh pheu: cac vien nam trong vong thuong cat cheo theo doc, kiem tra va chia vien rieng."))))))
          (princ "\n[SD] Can chon polyline kin."))
        (princ "\n[SD] Chua chon."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDMOANH - Mo bien anh da: khi bien moi cua vien vuot ra ngoai anh nhung tam da con du kho, tu dich anh roi cat lai
;;; --------------------------------------------------------------------------
;; Hinh hoc anh trong WCS: (goc-trai-duoi goc-xoay rong cao)
(defun sd:im-geom (e / o)
  (setq o (vlax-ename->vla-object e))
  (list (sd:2d (vlax-safearray->list (vlax-variant-value (vla-get-Origin o)))) (vla-get-Rotation o) (vla-get-Width o) (vla-get-Height o)))

;; Vec to dich anh (WCS) de da giac pts nam tron trong anh, chua le m moi canh khi du cho; (0 0) neu da nam trong; nil neu da giac lon hon anh
(defun sd:im-fit (g pts m / o a w h lp x0 x1 y0 y1 mm dx dy)
  (setq o (car g) a (cadr g) w (caddr g) h (cadddr g)
        lp (mapcar '(lambda (q) (sd:w2l o a q)) pts)
        x0 (apply 'min (mapcar 'car lp)) x1 (apply 'max (mapcar 'car lp))
        y0 (apply 'min (mapcar 'cadr lp)) y1 (apply 'max (mapcar 'cadr lp)))
  (if (or (> (- x1 x0) (+ w 1e-6)) (> (- y1 y0) (+ h 1e-6)))
    nil
    (progn
      (setq mm (max 0.0 (min m (/ (- w (- x1 x0)) 2.0) (/ (- h (- y1 y0)) 2.0)))
            dx (cond ((< x0 mm) (- mm x0)) ((> x1 (- w mm)) (- (- w mm) x1)) (t 0.0))
            dy (cond ((< y0 mm) (- mm y0)) ((> y1 (- h mm)) (- (- h mm) y1)) (t 0.0)))
      (sd:rot (list (- dx) (- dy)) a))))

;; Anh dung tam vien nam trong da giac (SD_ANH ghi luc SDANHDA), nil neu khong co
;; Da giac cat (IMAGECLIP) cua anh theo toa do WCS; nil neu anh khong bat cat. DXF IMAGE: 10 goc, 11 / 12 vec to 1 diem anh, 14 dinh cat (pixel, tam diem anh = so nguyen)
(defun sd:im-clip-pts (e / ed ins u v r q)
  (setq ed (entget e) ins (cdr (assoc 10 ed)) u (cdr (assoc 11 ed)) v (cdr (assoc 12 ed)))
  (if (and ins u v (= 1 (cond ((cdr (assoc 280 ed))) (0))))
    (progn
      (foreach g ed (if (= (car g) 14) (setq r (cons (list (cadr g) (caddr g)) r))))
      (setq r (reverse r))
      ;; clip chu nhat luu 2 goc doi: mo ra 4 goc trong he pixel
      (if (= (length r) 2)
        (setq r (list (car r) (list (car (cadr r)) (cadr (car r))) (cadr r) (list (car (car r)) (cadr (cadr r))))))
      (if (> (length r) 2)
        (mapcar '(lambda (q)
                   (list (+ (car ins) (* (+ (car q) 0.5) (car u)) (* (+ (cadr q) 0.5) (car v)))
                         (+ (cadr ins) (* (+ (car q) 0.5) (cadr u)) (* (+ (cadr q) 0.5) (cadr v)))))
                r)))))

;; Tam duong cat cua moi anh trong ban ve: ((ename cx cy) ...); doc 1 lan, xoa bo nho (nil) khi anh bi sua / sau moi lenh SD
(defun sd:im-clips (/ ss i e pc n)
  (if (null *SD:IMCLIPS*)
    (progn
      (setq *SD:IMCLIPS* (list 'OK))
      (if (setq ss (ssget "_X" '((0 . "IMAGE"))))
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq e (ssname ss i) i (1+ i))
            (if (setq pc (vl-catch-all-apply 'sd:im-clip-pts (list e)))
              (if (not (vl-catch-all-error-p pc))
                (setq n (float (length pc))
                      *SD:IMCLIPS* (cons (list e (/ (apply '+ (mapcar 'car pc)) n) (/ (apply '+ (mapcar 'cadr pc)) n)) *SD:IMCLIPS*)))))))))
  (cdr *SD:IMCLIPS*))

;; Anh co duong cat trung vien (tam cach tam vien <= max(15 mm, 10% ban kinh)): tim theo vi tri that, khong can SD_ANH
(defun sd:im-find-clip (cx cy rad / best d)
  (foreach c (sd:im-clips)
    (setq d (distance (list cx cy) (list (cadr c) (caddr c))))
    (if (and (<= d (max 15.0 (* 0.1 rad))) (or (null best) (< d (car best)))) (setq best (list d (car c)))))
  (cadr best))

(defun sd:im-find (pts ims / i e xd r cx cy rad d best cl)
  (setq i 0 cx (/ (apply '+ (mapcar 'car pts)) (float (length pts))) cy (/ (apply '+ (mapcar 'cadr pts)) (float (length pts)))
        rad (apply 'max (mapcar '(lambda (q) (distance (list cx cy) q)) pts))
        cl (sd:im-find-clip cx cy rad))
  (if (and (null cl) ims)
    (repeat (sslength ims)
      (setq e (ssname ims i) i (1+ i)
            xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_ANH"))))))
      (if (>= (length xd) 2)
        (progn
          (if (and (null r) (sd:inpoly (list (car xd) (cadr xd)) pts)) (setq r e))
          ;; du phong: bien da keo lech khoi tam cu thi lay anh co tam gan nhat trong ban kinh vien
          (setq d (distance (list cx cy) (list (car xd) (cadr xd))))
          (if (and (<= d (+ rad 50.0)) (or (null best) (< d (car best)))) (setq best (list d e)))))))
  (cond (cl) (r) ((cadr best))))

;; Goc xoay anh so voi canh dai vien (rad) da ghi luc SDANHDA, nil neu khong co hoac luoi chung (99)
(defun sd:im-delta (im / xd)
  (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget im '("SD_ANH"))))))
  (if (and (>= (length xd) 3) (< (abs (nth 2 xd)) 50.0)) (nth 2 xd)))

;; Xoay anh de van giu dung huong so voi canh dai moi cua vien: oldang = goc canh dai truoc khi sua (neu anh chua co du lieu goc)
(defun sd:im-rotfix (im pts oldang / fr o cur d df)
  (setq *SD:IFRAME* nil fr (sd:tile-frame pts))
  (if (> (abs (- (cadr fr) (caddr fr))) (* 0.02 (max (cadr fr) (caddr fr))))
    (progn
      (setq o (vlax-ename->vla-object im) cur (vla-get-Rotation o)
            d (cond ((sd:im-delta im)) (oldang (- cur oldang))))
      (if d
        (progn
          (setq df (rem (- (+ (car fr) d) cur) pi))
          (cond ((> df (/ pi 2.0)) (setq df (- df pi))) ((< df (/ pi -2.0)) (setq df (+ df pi))))
          (if (> (abs df) 1e-3)
            (vla-Rotate o (vlax-3d-point (car (nth 3 fr)) (cadr (nth 3 fr)) 0.0) df))))))
  t)

;; Cat lai anh im theo da giac pts: xoay lai van neu canh dai doi huong, dich anh neu can de du kho (le m). Tra ve OK, DICH hoac KHO
(defun sd:im-turn (im pts m / o xd c dl)
  (setq o (vlax-ename->vla-object im)
        xd (mapcar 'cdr (cdadr (assoc -3 (entget im '("SD_ANH")))))
        c (list (/ (apply '+ (mapcar 'car pts)) (float (length pts))) (/ (apply '+ (mapcar 'cadr pts)) (float (length pts))) 0.0))
  (vla-Rotate o (vlax-3d-point c) (/ pi 2.0))
  (if (sd:im-fit (sd:im-geom im) pts m)
    t
    (progn (vla-Rotate o (vlax-3d-point c) (/ pi -2.0)) nil)))

;; Het kho theo chieu hien tai: thu xoay anh 90 do quanh tam vien (cfg XOAY-KHO: Hoi / Tuxoay / Tat); chi anh rieng tung vien (co goc xoay)
(defun sd:im-try-turn (im pts m / mode xd c o ok)
  (setq mode (sd:cfg "XOAY-KHO" "Hoi"))
  (if (and (/= mode "Tat") (sd:im-delta im) (sd:im-turn im pts m))
    (cond
      ((or (= mode "Tuxoay") (and (= mode "Hoi") (not *SD:RXBUSY*) (progn (initget "Co Khong")
             (= (getkword "\nHet kho theo chieu van nay, xoay van 90 do thi du kho. Xoay? [Co/Khong] <Khong>: ") "Co"))))
       (setq xd (mapcar 'cdr (cdadr (assoc -3 (entget im '("SD_ANH"))))))
       (vl-catch-all-apply 'sd:put-xd
         (list im (list -3 (list "SD_ANH" (cons 1040 (car xd)) (cons 1040 (cadr xd))
                                 (cons 1040 (rem (+ (nth 2 xd) (/ pi 2.0)) (* 2.0 pi)))))))
       (princ "\n[SD] Da xoay van 90 do cho du kho (van doi chieu so voi cac vien ke).")
       t)
      (t ;; khong dong y / khong hoi duoc: tra anh ve cu
       (setq o (vlax-ename->vla-object im)
             c (list (/ (apply '+ (mapcar 'car pts)) (float (length pts))) (/ (apply '+ (mapcar 'cadr pts)) (float (length pts))) 0.0))
       (vla-Rotate o (vlax-3d-point c) (/ pi -2.0))
       (if (and (= mode "Hoi") *SD:RXBUSY*) (setq *SD:XOAYHINT* t))
       nil))))

;; Anh chon bang tay ma chua co SD_ANH (tam da goc / anh chen chua cat): khong cat de len anh goc, tao ban sao rieng cho vien
(defun sd:im-adopt (e pts / o cp ne c pc d rad yn)
  (setq c (list (/ (apply '+ (mapcar 'car pts)) (float (length pts))) (/ (apply '+ (mapcar 'cadr pts)) (float (length pts))))
        rad (apply 'max (mapcar '(lambda (q) (distance c q)) pts)))
  ;; anh dang cat o cho khac (co the la anh cua vien khac): hoi lai, tranh keo anh vien khac ve day
  (if (and (setq pc (vl-catch-all-apply 'sd:im-clip-pts (list e))) (not (vl-catch-all-error-p pc)) pc
           (> (setq d (distance c (list (/ (apply '+ (mapcar 'car pc)) (float (length pc))) (/ (apply '+ (mapcar 'cadr pc)) (float (length pc))))))
              (max 50.0 (* 0.3 rad))))
    (progn
      (initget "Co Khong")
      (setq yn (getkword (strcat "\n[SD] Anh nay dang cat cach vien " (sd:num d) " mm (co the la anh cua vien khac). Van dung anh nay? [Co/Khong] <Khong>: ")))
      (if (/= yn "Co") (setq e nil))))
  (cond
    ((null e) nil)
    ((cdr (assoc -3 (entget e '("SD_ANH")))) e)
    (t
     (setq o (vlax-ename->vla-object e) cp (vla-Copy o) ne (vlax-vla-object->ename cp))
     (vl-catch-all-apply 'vla-put-Layer (list cp "SD-GACH-ANH"))
     (vl-catch-all-apply 'sd:put-xd
       (list ne (list -3 (list "SD_ANH" (cons 1040 (float (car c))) (cons 1040 (float (cadr c))) (cons 1040 99.0)))))
     (princ "\n[SD] Anh chon chua phai anh da cat cua vien (khong co du lieu SD_ANH, co the la tam goc): giu nguyen anh goc, tao ban sao de cat cho vien nay.")
     ne)))

(defun sd:im-reclip (im pts m oldang / g d tr os)
  (sd:im-rotfix im pts oldang)
  (setq g (sd:im-geom im) d (sd:im-fit g pts m))
  (if (and (null d) (sd:im-try-turn im pts m))
    (setq tr t g (sd:im-geom im) d (sd:im-fit g pts m)))
  (cond
    ((null d) 'KHO)
    (t
     (if (> (distance '(0.0 0.0) d) 1e-6)
       (vla-Move (vlax-ename->vla-object im) (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point (car d) (cadr d) 0.0)))
     (setq os (getvar "OSMODE")) (setvar "OSMODE" 0)
     (command "_.IMAGECLIP" im "_D")
     (command "_.IMAGECLIP" im "_N" "_P")
     (foreach q pts (command (trans (list (car q) (cadr q) 0.0) 0 1)))
     (command "")
     (setvar "OSMODE" os)
     (setq *SD:IMCLIPS* nil)
     (cond (tr 'XOAY) ((> (distance '(0.0 0.0) d) 1e-6) 'DICH) (t 'OK)))))

(defun c:SDMOANH (/ ss ims i e pts im m tay n nmv nfar nnone r st)
  (sd:begin)
  (if (sd:dlg "Mo bien anh da (SDMOANH)"
              (list (list "m" "Chua le an toan moi canh khi du kho (mm)" 'real0 (sd:cfg "MOANH-M" 10.0))
                    (list "tay" "Khong tu ghep duoc anh thi hoi chon anh bang tay" 'tog t)
                    (list "xoay" "Het kho thi xoay van 90 do quanh tam vien (SDTUDONG cung dung)" 'kw (sd:cfg "XOAY-KHO" "Hoi")
                          '(("Hoi" . "Hoi truoc khi xoay") ("Tuxoay" . "Tu xoay va bao") ("Tat" . "Khong xoay, bao het kho")))))
    (progn
      (sd:cfg-put "XOAY-KHO" (cond ((sd:v "xoay")) ("Hoi")))
      (setq m (sd:cfg-put "MOANH-M" (sd:v "m")) tay (sd:v "tay") n 0 nmv 0 nfar 0 nnone 0)
      (princ "\nChon cac polyline bien moi (da chinh) cua vien: ")
      (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
        (progn
          (setq ims (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH")))) i 0)
          (repeat (sslength ss)
            (setq e (ssname ss i) i (1+ i) pts (sd:curve-pts e) im (sd:im-find pts ims) n (1+ n))
            (if (and (null im) tay)
              (progn
                (princ (strcat "\nVien " (itoa n) ": khong tu ghep duoc anh."))
                (if (setq r (entsel "\nChon anh cua vien nay <bo qua>: "))
                  (if (= (cdr (assoc 0 (entget (car r)))) "IMAGE") (setq im (sd:im-adopt (car r) pts))))))
            (if (null im)
              (setq nnone (1+ nnone))
              (progn
                (setq st (sd:im-reclip im pts m nil))
                (cond ((= st 'KHO) (setq nfar (1+ nfar))
                       (princ (strcat "\nVien " (itoa n) ": bien lon hon ca tam da, khong du kho.")))
                      ((member st '(DICH XOAY)) (setq nmv (1+ nmv)))))))
          (princ (strcat "\n[SD] " (itoa (sslength ss)) " vien: cat lai theo bien moi " (itoa (- (sslength ss) nfar nnone)) ", trong do dich anh "
                         (itoa nmv) " vien; het kho " (itoa nfar) "; khong co anh " (itoa nnone) ".")))
        (princ "\n[SD] Chua chon polyline."))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDRON - Doi ron giua cac vien: thu / phong cac polyline vien tai cho, cap nhat hatch lien ket va cat lai anh, khong phai sua tay
;;; --------------------------------------------------------------------------
;; Chep dinh (va cung) cua polyline e2 vao polyline e, giu nguyen layer, du lieu SD_TILE va lien ket hatch
(defun sd:poly-vertsfrom (e e2 / a b pre post mid vs n)
  (setq a (entget e '("SD_TILE")) b (entget e2))
  (foreach g a
    (cond ((member (car g) '(10 40 41 42)) (setq mid t))
          (mid (setq post (cons g post)))
          (t (setq pre (cons g pre)))))
  (setq vs (vl-remove-if-not '(lambda (g) (member (car g) '(10 40 41 42))) b)
        n (length (vl-remove-if-not '(lambda (g) (= (car g) 10)) b))
        pre (mapcar '(lambda (g) (if (= (car g) 90) (cons 90 n) g)) (reverse pre)))
  (entmod (append pre vs (reverse post))))

(defun c:SDRON (/ ss ims hs i e pts e2 d cu moi anh hat ronanh im st n nok nfail nimg nkho nhas nhn nmiss)
  (sd:begin)
  (if (sd:dlg "Doi ron giua cac vien (SDRON)"
              (list (list "cu" "Ron hien tai giua cac vien (mm) - tu lay tu SDGACH / SDLOT / lan doi truoc" 'real0 (cond (*SD:GJ*) ((sd:cfg "RON-CU" 2.0))))
                    (list "moi" "Ron moi (mm) - bang ron hien tai thi chi dong bo anh / hatch" 'real0 (sd:cfg "RON-MOI" 4.0))
                    (list "hat" "Cap nhat hatch van da lien ket" 'tog t)
                    (list "anh" "Cat lai anh IMAGECLIP theo bien moi" 'tog t)
                    (list "ronanh" "Ron chua them trong anh (mm, nhu o Ron cua SDANHDA)" 'real0 (sd:cfg "RON-ANH" 0.0))))
    (progn
      (setq nmiss 0 cu (sd:cfg-put "RON-CU" (sd:v "cu")) moi (sd:cfg-put "RON-MOI" (sd:v "moi")) hat (sd:v "hat") anh (sd:v "anh")
            ronanh (sd:cfg-put "RON-ANH" (sd:v "ronanh")) d (/ (- moi cu) 2.0) n 0 nok 0 nfail 0 nimg 0 nkho 0)
      (princ "\nChon cac polyline vien can doi ron <Enter = tat ca vien tren layer SD-GACH / SD-GACH-CAT / SD-GACH-VIEN / SD-GACH-DOC>: ")
      (if (setq ss (cond ((ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
                         ((ssget "_X" '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT,SD-GACH-VIEN,SD-GACH-DOC") (-4 . "&") (70 . 1))))))
        (progn
          (if (< (abs d) 1e-6) (princ "\n[SD] Ron moi bang ron cu: chi dong bo anh va hatch theo bien hien tai (khong doi kich thuoc vien)."))
          (progn
            (setq ims (if anh (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH"))))) i 0)
            (repeat (sslength ss)
              (setq e (ssname ss i) i (1+ i) n (1+ n) pts (sd:curve-pts e) im (if ims (sd:im-find pts ims))
                    e2 (if (< (abs d) 1e-6) e (sd:offset e (abs d) (> d 0.0))))
              (if e2
                (progn
                  (if (not (equal e2 e)) (sd:poly-vertsfrom e e2))
                  (setq nok (1+ nok))
                  (if im
                    (progn
                      (setq st (sd:im-reclip im (sd:inset-pts (sd:curve-pts e) (/ ronanh 2.0)) 10.0 nil))
                      (cond ((= st 'KHO) (setq nkho (1+ nkho))) (t (setq nimg (1+ nimg)))))
                    (if anh (setq nmiss (1+ nmiss)))))
                (setq nfail (1+ nfail))))
            (if hat
              (progn
                (setq hs (ssget "_X" '((0 . "HATCH") (8 . "SD-GACH-VAN"))) nhas 0 nhn 0)
                (if hs
                  (repeat (sslength hs)
                    (setq e (ssname hs nhas) nhas (1+ nhas))
                    (if (= (vla-get-AssociativeHatch (vlax-ename->vla-object e)) :vlax-true)
                      (vl-catch-all-apply 'vla-Evaluate (list (vlax-ename->vla-object e)))
                      (setq nhn (1+ nhn)))))))
            (if (> nok 0) (setq *SD:GJ* (sd:cfg-put "RON-CU" moi)))
            (princ (strcat "\n[SD] Doi ron " (sd:num cu) " -> " (sd:num moi) " mm: " (itoa nok) " / " (itoa n) " vien"
                           (if (> nfail 0) (strcat ", khong doi duoc " (itoa nfail) " vien (bien qua nho / lom)") "")
                           (if anh (strcat "; cat lai anh " (itoa nimg) " vien" (if (> nkho 0) (strcat ", het kho " (itoa nkho)) "")) "") "."))
            (if (and anh (> nmiss 0))
              (princ (strcat "\n[SD] " (itoa nmiss) " vien khong tim thay anh de cat lai (anh tao bang SDANHDA ban cu khong co du lieu SD_ANH): chay lai SDANHDA cho cac vien nay, hoac SDMOANH va chon anh bang tay.")))
            (if (and hat nhn (> nhn 0))
              (princ (strcat "\n[SD] " (itoa nhn) " hatch chua lien ket voi bien (tao tu ban cu): chay lai SDVANDA tren cac vien de hatch lien ket tu sau.")))))
        (princ "\n[SD] Chua chon polyline."))))
  (sd:finish))

;; Thu nho da giac vien vao trong d (mm) de chua ron: tra ve dinh moi, hoac chinh da giac cu neu khong thu duoc
(defun sd:inset-pts (pts d / e0 e1 r)
  (if (<= d 1e-6)
    pts
    (progn
      (sd:pline pts t "SD-GACH")
      (setq e0 (entlast) e1 (sd:offset e0 d t))
      (setq r (cond ((and e1 (>= (length (setq r (sd:curve-pts e1))) 3)) r) (t pts)))
      (entdel e0)
      r)))

;; Huong van "vien chinh": chon 1 vien nguyen (Enter = vien co khung lon nhat); tra ve goc canh dai cua vien do (rad)
(defun sd:main-ang (els / sel e pts best fr a sv)
  (princ "\nChon 1 vien chinh lam huong van (Enter = vien lon nhat trong cac vien dang cat): ")
  (setq sel (vl-catch-all-apply 'entsel nil) sv *SD:IFRAME* *SD:IFRAME* nil)
  (if (and sel (not (vl-catch-all-error-p sel)) (setq e (car sel)) (= (cdr (assoc 0 (entget e))) "LWPOLYLINE")
           (>= (length (setq pts (sd:curve-pts e))) 3))
    (setq a (car (sd:tile-frame pts)))
    (foreach e els
      (if (>= (length (setq pts (sd:curve-pts e))) 3)
        (progn (setq fr (sd:tile-frame pts))
               (if (or (null best) (> (* (cadr fr) (caddr fr)) (car best))) (setq best (list (* (cadr fr) (caddr fr)) (car fr))))))))
  (if (and (null a) best) (setq a (cadr best)))
  (setq *SD:IFRAME* sv)
  a)

(defun sd:anhda (els / mflag sw sh trim kerf chieu xep ss i e pts fr tiles imst items bases res pls nsl n k rec pl tot pt sc m ti tuanh io ctc vun cuts remn nq ron front sf win inron layerx doilay nlay)
  (setq sc (sd:sc))
  (if (sd:dlg "Cat anh da vao vien (SDANHDA)"
                   (list (list "tuanh" "Lay kich thuoc tam tu anh da chen (anh dung ti le that)" 'tog (if (member *SD:ITUANH* '(0)) nil t))
                         (list "sw" "Tam da tho - dai that (mm) (bo qua neu lay tu anh)" 'real (cond (*SD:ISW*) (3000.0)))
                         (list "sh" "Tam da tho - rong that (mm) (bo qua neu lay tu anh)" 'real (cond (*SD:ISH*) (1600.0)))
                         (list "trim" "Xen bien tam (mm)" 'real0 (cond (*SD:ITRIM*) (20.0)))
                         (list "kerf" "Be rong luoi cat (mm)" 'real0 (cond (*SD:IKERF*) (4.0)))
                         (list "chieu" "Chieu van tren vien" 'kw (cond (*SD:ICHIEU*) ("Toiuu"))
                               '(("Toiuu" . "Tu xoay 90 do de it hao") ("Doc" . "Van theo canh dai vien") ("Ngang" . "Van vuong goc canh dai") ("Chinh" . "Van theo huong vien chinh (chon 1 vien, moi vien deu 1 huong)")))
                         (list "xep" "Cach xep vien vao tam" 'kw (cond (*SD:IXEP*) ("Toiuu"))
                               '(("Toiuu" . "It hao nhat: cat xuyen, manh nho lap vao phe lieu hinh L / vun") ("Thutu" . "Theo thu tu lat (van gan nhau)")
                                 ("Duongviem" . "Chay doc duong vien (van lien tuc, vien sau ngay sau vien truoc)")))
                         (list "nq" "Do ky khi xep (cat xuyen: thu nhieu cach, chon it tam nhat)" 'kw (cond (*SD:INQ*) ("Canbang"))
                               '(("Nhanh" . "Nhanh: 1 cach xep") ("Canbang" . "Can bang: thu 30 to hop sap xep / cham diem / tach o") ("Ky" . "Ky: them leo doi hoan doi thu tu (toi da ~6 giay)"))
                               '("xep" "Toiuu"))
                         (list "win" "Thu tu lat: moi tam nhin truoc bao nhieu vien de lap cho trong (1 = dung thu tu tuyet doi)" 'int (cond (*SD:IWIN*) (6))
                               nil '("xep" "Thutu" "Duongviem"))
                         (list "ctc" "Ve thu tu duong cat + phe lieu (cat xuyen, cho che do It hao)" 'tog t)
                         (list "vun" "Phe lieu ghi nhan khi ca 2 canh >= (mm)" 'real0 (cond (*SD:IVUN*) (150.0)))
                         (list "ron" "Khe chua them trong anh (mm, mac dinh 0: chi dung ron that cua vien; chi tang neu muon khe trang hon ron)" 'real0 (cond (*SD:IRON*) (0.0)))
                         (list "inron" "Tu dat mau ron de in (trang tren da toi, nhu SDRONIN)" 'tog (cond (*SD:IINRON*) (t)))
                         (list "doilay" "Doi polyline vien (VD boundary tu hatch) sang layer SD-GACH-DOC de co ron khi in (SDRONIN / SDIN tac dong)" 'tog (sd:cfg "ANHDA-DOILAY" t))
                         (list "layerx" "Bo qua cac layer (VD *STAIR*,*THANG*,*MUI*; cach nhau dau phay; trong = khong bo)" 'str (sd:cfg "LAYERX" ""))
                         (list "front" "Dua duong vien (polyline) len tren anh de thay ron khi in" 'tog (cond (*SD:IFRONT*) (t)))))
   (progn
  (setq sw (sd:v "sw") sh (sd:v "sh") trim (sd:v "trim") kerf (sd:v "kerf") chieu (sd:v "chieu") xep (sd:v "xep")
        tuanh (sd:v "tuanh") *SD:ITUANH* (if tuanh 1 0) ctc (sd:v "ctc") vun (sd:v "vun") *SD:IVUN* vun
        win (cond ((sd:v "win")) (6)) *SD:IWIN* win
        ron (cond ((sd:v "ron")) (0.0)) *SD:IRON* ron front (sd:v "front") *SD:IFRONT* front
        doilay (sd:cfg-put "ANHDA-DOILAY" (sd:v "doilay"))
        inron (sd:v "inron") *SD:IINRON* inron layerx (sd:cfg-put "LAYERX" (cond ((sd:v "layerx")) ("")))
        nq (cond ((sd:v "nq")) ("Canbang")) *SD:INQ* nq
        *SD:ITRIM* trim *SD:IKERF* kerf *SD:ICHIEU* chieu *SD:IXEP* xep)
  (princ "\nChon anh tam da tho (nhieu anh cung kich thuoc that = nhieu tam khac van): ")
  (if (null (setq ss (ssget '((0 . "IMAGE")))))
    (princ "\n[SD] Chua chon anh.")
    (progn
      (if tuanh
        (progn
          (setq io (vlax-ename->vla-object (ssname ss 0)) sw (vla-get-Width io) sh (vla-get-Height io))
          (princ (strcat "\n[SD] Kich thuoc tam lay tu anh: " (sd:num sw) " x " (sd:num sh) " mm")))
        (setq *SD:ISW* sw *SD:ISH* sh))
      (setq i 0)
      (repeat (sslength ss) (setq imst (cons (sd:img-master (ssname ss i) sw sh) imst) i (1+ i)))
      (setq imst (reverse imst))
      (if (null els)
        (progn
          (princ "\nQuet chon cac polyline kin la vien da can cat anh: ")
          (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
            (progn (setq i 0)
                   (repeat (sslength ss) (setq els (cons (ssname ss i) els) i (1+ i)))))))
      (if (and els layerx (/= layerx ""))
        (progn
          (setq n (length els)
                els (vl-remove-if '(lambda (e) (wcmatch (strcase (cdr (assoc 8 (entget e)))) (strcase layerx))) els))
          (if (< (length els) n)
            (princ (strcat "\n[SD] Bo qua " (itoa (- n (length els))) " polyline tren layer " layerx ".")))))
      (if (null els)
        (princ "\n[SD] Chua chon vien nao.")
        (progn
          (if (and (= chieu "Chinh") (not *SD:IFRAME*))
            (if (setq fr (sd:main-ang els))
              (setq *SD:IFRAME* fr mflag t)
              (setq chieu "Doc")))
          (setvar "OSMODE" 0)
          (foreach e els
            (if (>= (length (setq pts (sd:curve-pts e))) 3)
              (progn
                (setq fr (sd:tile-frame pts))
                (setq tiles (cons (list "" pts (car fr) (cadr fr) (caddr fr) (cadddr fr)) tiles)))
              (princ "\n[SD] Bo qua 1 polyline khong doc duoc dinh (loi hoac <3 dinh).")))
          (if (null tiles) (progn (princ "\n[SD] Khong co vien hop le de cat anh.") (if mflag (setq *SD:IFRAME* nil)) (exit)))
          (setq tiles (if (= xep "Duongviem") (sd:tile-chain (reverse tiles)) (sd:tile-order (reverse tiles))) i 0)
          (setq tiles (mapcar '(lambda (r) (setq i (1+ i)) (cons (strcat "T" (itoa i)) (cddr r))) tiles))
          ;; moi vien: (id pts ang tw th cw); kich thuoc dua vao xep + goc nen
          (foreach r tiles
            (cond
              ;; luoi rai co khung chung: Doc = van theo canh dai tam luoi cho moi vien, Ngang = vuong goc, Toiuu = duoc xoay 90
              ((and *SD:IFRAME* (= chieu "Ngang"))
               (setq items (cons (list (car r) (nth 4 r) (nth 3 r)) items) bases (cons (cons (car r) (+ (nth 2 r) (/ pi 2.0))) bases)))
              (*SD:IFRAME*
               (setq items (cons (list (car r) (nth 3 r) (nth 4 r)) items) bases (cons (cons (car r) (nth 2 r)) bases)))
              ((= chieu "Doc")
               (if (>= (nth 3 r) (nth 4 r))
                 (setq items (cons (list (car r) (nth 3 r) (nth 4 r)) items) bases (cons (cons (car r) (nth 2 r)) bases))
                 (setq items (cons (list (car r) (nth 4 r) (nth 3 r)) items) bases (cons (cons (car r) (+ (nth 2 r) (/ pi 2.0))) bases))))
              ((= chieu "Ngang")
               (if (>= (nth 3 r) (nth 4 r))
                 (setq items (cons (list (car r) (nth 4 r) (nth 3 r)) items) bases (cons (cons (car r) (+ (nth 2 r) (/ pi 2.0))) bases))
                 (setq items (cons (list (car r) (nth 3 r) (nth 4 r)) items) bases (cons (cons (car r) (nth 2 r)) bases))))
              (t (setq items (cons (list (car r) (nth 3 r) (nth 4 r)) items) bases (cons (cons (car r) (nth 2 r)) bases)))))
          (setq items (reverse items)
                res (if (= xep "Toiuu")
                      (sd:nest-g items sw sh trim kerf (= chieu "Toiuu") vun (cond ((= nq "Nhanh") 0) ((= nq "Ky") 2) (t 1)))
                      (sd:nest-w items sw sh trim kerf (and (= chieu "Toiuu") (/= xep "Duongviem")) vun win))
                pls (car res) nsl (cadr res) cuts (caddr res) remn (cadddr res) n 0 tot 0.0)
          (foreach pl pls
            (setq rec (assoc (car pl) tiles))
            (if (cadr pl)
              (progn
                (sd:img-place (nth (rem (cadr pl) (length imst)) imst) pl (cdr (assoc (car pl) bases)) (nth 5 rec) (sd:inset-pts (nth 1 rec) (/ ron 2.0)))
                (setq n (1+ n) tot (+ tot (* (nth 3 rec) (nth 4 rec)))))
              (princ (strcat "\n[SD] Vien " (car pl) " (" (sd:num (nth 3 rec)) " x " (sd:num (nth 4 rec)) ") lon hon tam da: khong cat duoc."))))
          (if front
            (progn
              (foreach e els (if (entget e) (setq sf (cond (sf) ((ssadd))) sf (ssadd e sf))))
              (if sf (command "_.DRAWORDER" sf "" "_F"))))
          (if doilay
            (progn
              (sd:make-layer "SD-GACH-DOC" 3 "Continuous" 13)
              (setq nlay 0)
              (foreach e els
                (if (and (entget e) (not (member (strcase (cdr (assoc 8 (entget e)))) *SD:RONLAY*))
                         (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-put-Layer (list (vlax-ename->vla-object e) "SD-GACH-DOC")))))
                  (setq nlay (1+ nlay))))
              (if (> nlay 0) (princ (strcat "\n[SD] Da doi " (itoa nlay) " polyline vien sang layer SD-GACH-DOC (co ron khi in).")))))
          (sd:ron-extra-add els)
          (if inron
            (sd:ronin-apply (cond ((/= (sd:cfg "RONIN-MAU" "Trang") "Khoiphuc") (sd:cfg "RONIN-MAU" "Trang")) ("Trang"))
                            (sd:cfg "RONIN-LW" 0.25) (sd:cfg "RONIN-MAP" "") t))
          (vlax-ldata-put "SD" "ANHDA"
            (mapcar '(lambda (pl) (list (car pl) (car (nth 5 (assoc (car pl) tiles))) (cadr (nth 5 (assoc (car pl) tiles))) (cadr pl)
                                        (nth 2 pl) (nth 3 pl) (nth 4 pl) (nth 5 pl)
                                        (if (cadr pl) (+ (cdr (assoc (car pl) bases)) (if (nth 6 pl) (/ pi 2.0) 0.0)))))
                    pls))
          (if (setq pt (sd:getpt "\nDiem chen so do cat tam da <bo qua>: " nil))
            (if (and ctc cuts) (sd:img-diagram2 pls nsl sw sh pt sc cuts remn) (sd:img-diagram pls nsl sw sh pt sc)))
          (foreach m imst (vl-catch-all-apply 'vla-Delete (list (car m))))
          (if mflag (setq *SD:IFRAME* nil))
          (princ (strcat "\n[SD] Da cat " (itoa n) " / " (itoa (length tiles)) " vien tu anh; can " (itoa nsl) " tam da " (sd:num sw) " x " (sd:num sh)
                         (if (> nsl 0) (strcat ", hao " (sd:num (* 100.0 (- 1.0 (/ tot (* nsl sw sh))))) "%") "")
                         (if (and (> nsl 1) (= (length imst) 1)) " (cac tam dung chung 1 anh nen van giong nhau; chon nhieu anh de doi van)" "")
                         "."))))))))
  (princ))

;; ---- Xep CAT XUYEN (guillotine) cho may cat da cau: danh sach o trong, uu tien manh lon, vien nho lap vao phe lieu hinh L / vun
;; Ghi lai duong cat kem cap (cap 0 = cat tach lon truoc, cap sau = cat manh nho sau cung) de danh so thu tu cat.
;; Tra ve (placements so-tam cuts phe-lieu): placement = (id tam x y rong cao xoay); cut = (tam x1 y1 x2 y2 cap); phe-lieu = (tam x y rong cao)
;; Mot luot xep cat xuyen: items da sap thu tu san; fm = cach cham diem o trong (0 it thua canh ngan nhat, 1 it thua canh dai nhat, 2 it thua dien tich);
;; sm = cach tach o trong (0 theo canh thua ngan, 1 theo canh thua dai, 2 giu o lon nhat, 3 luon ngang truoc, 4 luon dung truoc)
(defun sd:nest-g1 (items SW SH trim kerf rotok vun fm sm / uw1 uh1 slabs pl cuts best it o cw ch si fr j f sc fx fy fw fh dep pw ph wf hf nf k rm hfirst lw lh)
  (setq uw1 (+ (- SW (* 2.0 trim)) kerf) uh1 (+ (- SH (* 2.0 trim)) kerf))
  (foreach it items
    (setq best nil)
    (foreach o (if rotok (list nil t) (list nil))
      (setq cw (+ kerf (if o (caddr it) (cadr it))) ch (+ kerf (if o (cadr it) (caddr it))) si 0)
      (foreach fr slabs
        (setq j 0)
        (foreach f fr
          (if (and (<= cw (+ (nth 2 f) 1e-6)) (<= ch (+ (nth 3 f) 1e-6)))
            (progn
              (setq lw (- (nth 2 f) cw) lh (- (nth 3 f) ch)
                    sc (cond ((= fm 1) (+ (* 1000.0 (max lw lh)) (/ (* (nth 2 f) (nth 3 f)) 1e6)))
                             ((= fm 2) (- (* (nth 2 f) (nth 3 f)) (* cw ch)))
                             (t (+ (* 1000.0 (min lw lh)) (/ (* (nth 2 f) (nth 3 f)) 1e6)))))
              ;; vua khit 1 canh: cat duoc ca dai, it duong cat, it vun -> uu tien manh
              (if (or (< lw 1.0) (< lh 1.0)) (setq sc (- sc 1e8)))
              (if (or (null best) (< sc (car best))) (setq best (list sc si j o cw ch nil)))))
          (setq j (1+ j)))
        (setq si (1+ si)))
      (if (and (<= cw (+ uw1 1e-6)) (<= ch (+ uh1 1e-6)))
        (progn
          (setq sc (+ 1e9 (* 1000.0 (min (- uw1 cw) (- uh1 ch)))))
          (if (or (null best) (< sc (car best))) (setq best (list sc (length slabs) 0 o cw ch t))))))
    (if best
      (progn
        (setq si (nth 1 best) j (nth 2 best) cw (nth 4 best) ch (nth 5 best))
        (if (nth 6 best) (setq slabs (append slabs (list (list (list trim trim uw1 uh1 0))))))
        (setq fr (nth si slabs) f (nth j fr)
              fx (car f) fy (cadr f) fw (caddr f) fh (cadddr f) dep (nth 4 f)
              pw (- cw kerf) ph (- ch kerf) wf (- fw cw) hf (- fh ch) nf nil
              hfirst (cond ((= sm 1) (> wf hf))
                           ((= sm 2) (>= (max (* fw hf) (* wf ch)) (max (* wf fh) (* cw hf))))
                           ((= sm 3) t)
                           ((= sm 4) nil)
                           (t (<= wf hf))))
        (cond
          (hfirst
           (if (> hf 1.0)
             (progn (setq nf (cons (list fx (+ fy ch) fw hf (1+ dep)) nf))
                    (setq cuts (cons (list si fx (+ fy ph) (+ fx fw -1.0) (+ fy ph) dep) cuts))))
           (if (> wf 1.0)
             (progn (setq nf (cons (list (+ fx cw) fy wf ch (1+ dep)) nf))
                    (setq cuts (cons (list si (+ fx pw) fy (+ fx pw) (+ fy ph) (1+ dep)) cuts)))))
          (t
           (if (> wf 1.0)
             (progn (setq nf (cons (list (+ fx cw) fy wf fh (1+ dep)) nf))
                    (setq cuts (cons (list si (+ fx pw) fy (+ fx pw) (+ fy fh -1.0) dep) cuts))))
           (if (> hf 1.0)
             (progn (setq nf (cons (list fx (+ fy ch) cw hf (1+ dep)) nf))
                    (setq cuts (cons (list si fx (+ fy ph) (+ fx pw) (+ fy ph) (1+ dep)) cuts))))))
        (setq slabs (sd:lset slabs si (append (sd:remove-nth j fr) nf)))
        (setq pl (cons (list (car it) si fx fy pw ph (nth 3 best)) pl)))
      (setq pl (cons (list (car it) nil nil nil nil nil nil) pl))))
  ;; phe lieu con lai (o trong du lon): vien nho ve sau co the dung lam ban nhap / van vun
  (setq k 0)
  (foreach fr slabs
    (foreach f fr
      (if (and (>= (- (nth 2 f) kerf) vun) (>= (- (nth 3 f) kerf) vun))
        (setq rm (cons (list k (car f) (cadr f) (- (nth 2 f) kerf) (- (nth 3 f) kerf)) rm))))
    (setq k (1+ k)))
  (list (reverse pl) (length slabs) (reverse cuts) (reverse rm)))

;; ---- ABF-style: nhieu cach sap xep / cham diem / tach o, chon ket qua tot nhat; do ky = leo doi (hoan doi thu tu) ----
;; Khoa so sanh ket qua: (so-vien-khong-xep so-tam dien-tich-dung-o-tam-cuoi so-duong-cat); nho hon la tot hon
(defun sd:ng-key (res / un lastu pl ns)
  (setq pl (car res) ns (cadr res) un 0 lastu 0.0)
  (foreach p pl
    (if (null (cadr p))
      (setq un (1+ un))
      (if (= (cadr p) (1- ns)) (setq lastu (+ lastu (* (nth 4 p) (nth 5 p)))))))
  (list un ns lastu (length (caddr res))))
(defun sd:ng-less (a b)
  (cond ((/= (car a) (car b)) (< (car a) (car b)))
        ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
        ((> (abs (- (caddr a) (caddr b))) 40000.0) (< (caddr a) (caddr b)))
        (t (< (cadddr a) (cadddr b)))))

;; Thu tu sap xep manh: 0 dien tich, 1 canh dai, 2 rong, 3 cao, 4 chu vi, 5 canh ngan
(defun sd:ng-sort (items m)
  (sd:sort items
    (cond ((= m 1) '(lambda (a b) (if (= (max (cadr a) (caddr a)) (max (cadr b) (caddr b)))
                                    (> (min (cadr a) (caddr a)) (min (cadr b) (caddr b)))
                                    (> (max (cadr a) (caddr a)) (max (cadr b) (caddr b))))))
          ((= m 2) '(lambda (a b) (if (= (cadr a) (cadr b)) (> (caddr a) (caddr b)) (> (cadr a) (cadr b)))))
          ((= m 3) '(lambda (a b) (if (= (caddr a) (caddr b)) (> (cadr a) (cadr b)) (> (caddr a) (caddr b)))))
          ((= m 4) '(lambda (a b) (> (+ (cadr a) (caddr a)) (+ (cadr b) (caddr b)))))
          ((= m 5) '(lambda (a b) (if (= (min (cadr a) (caddr a)) (min (cadr b) (caddr b)))
                                    (> (max (cadr a) (caddr a)) (max (cadr b) (caddr b)))
                                    (> (min (cadr a) (caddr a)) (min (cadr b) (caddr b))))))
          (t '(lambda (a b) (> (* (cadr a) (caddr a)) (* (cadr b) (caddr b))))))))

;; q: 0 nhanh (1 cach: dien tich giam dan, it thua canh ngan, tach theo canh thua ngan), 1 can bang (30 to hop sap xep x cham diem x tach o), 2 ky (them leo doi trong gioi han thoi gian)
;; Thu nghiem 12 bo: tach theo canh thua dai (sm 1) thang nhieu nhat; sap theo canh dai / cao truoc; fm 0 va 2
(defun sd:nest-g (items SW SH trim kerf rotok vun q / sorts fms sms best bk res k s fm sm ord n cur curk seed i j a b nb iter t0 bs bfm bsm bord)
  (setq q (cond (q) (0))
        sorts (if (= q 0) '(0) '(1 3 0 2 5))
        fms (if (= q 0) '(0) '(0 2))
        sms (if (= q 0) '(0) '(1 2 0)))
  (foreach s sorts
    (setq ord (sd:ng-sort items s))
    (foreach fm fms
      (foreach sm sms
        (setq res (sd:nest-g1 ord SW SH trim kerf rotok vun fm sm) k (sd:ng-key res))
        (if (or (null bk) (sd:ng-less k bk)) (setq best res bk k bord ord bfm fm bsm sm)))))
  ;; leo doi: hoan doi 2 manh trong thu tu tot nhat, nhan neu khong te hon
  (if (and (>= q 2) (> (length items) 3) (> (car (cdr bk)) 1))
    (progn
      (setq seed 12345.0 n (length bord) cur bord curk bk iter 0 t0 (getvar "MILLISECS"))
      (while (and (< iter 800) (< (- (getvar "MILLISECS") t0) 6000.0) (> (car (cdr bk)) 1))
        (setq seed (rem (+ (* seed 1664525.0) 1013904223.0) 4294967296.0) i (fix (* n (/ seed 4294967296.0)))
              seed (rem (+ (* seed 1664525.0) 1013904223.0) 4294967296.0) j (fix (* n (/ seed 4294967296.0)))
              iter (1+ iter))
        (if (/= i j)
          (progn
            (setq a (nth i cur) b (nth j cur) nb (sd:lset (sd:lset cur i b) j a)
                  res (sd:nest-g1 nb SW SH trim kerf rotok vun bfm bsm) k (sd:ng-key res))
            (if (not (sd:ng-less curk k))
              (progn (setq cur nb curk k)
                     (if (sd:ng-less k bk) (setq best res bk k))))))))
    )
  best)

;; So thu tu duong cat theo tung tam: cap nho (cat tach lon) truoc, manh nho cat sau cung
(defun sd:cut-seq (cuts)
  (sd:sort cuts '(lambda (a b)
                   (cond ((/= (car a) (car b)) (< (car a) (car b)))
                         ((/= (nth 5 a) (nth 5 b)) (< (nth 5 a) (nth 5 b)))
                         ((/= (cadr a) (cadr b)) (< (cadr a) (cadr b)))
                         (t (< (caddr a) (caddr b)))))))

;; So do cat: khung tam + vien + duong cat danh so thu tu + phe lieu
(defun sd:img-diagram2 (pls nsl SW SH pt sc cuts remn) (sd:dg-draw pls nsl SW SH pt sc cuts remn))

(defun c:SDRAITAM (/ mode kho stk0 stk std W H jt hu van mat name thk idt sc ss i polys rooms holes room
                     outer lps loops edges R tr bb x0 y0 px py nx ny ci cj ii cx cy cs lcs cls cl gx gy gw gh
                     fit used bom pt nfull ncut ntim atim nroom pieces seq vd vp lvp rc rows n fn f rw pe vph vps
                     ang fa fo kieu off shf lo lb lx0 lx1 ly0 ly1 wg ianh e0 p0)
  (sd:begin)
  (setq sc (sd:sc) e0 (entlast))
  (if (not (sd:dlg "Rai panel / da lat theo kho (SDRAITAM)"
                   (list (list "mode" "Che do" 'kw (cond (*SD:RTMODE*) ("Panel"))
                               '(("Panel" . "Panel (kho tam + go bu INFILL-TIMBER)") ("Da" . "Da / gach lat (vien cat + huong van)")))
                         (list "kho" "Kho tam: RxD:so-luong, ... (0 / bo trong = khong han che)" 'str
                               (cond (*SD:RTKHO*) ("600x1200,450x1200,400x1200,300x1200,200x1200")))
                         (list "hu" "Canh dai cua tam song song truc" 'kw (cond (*SD:RTHU*) ("Y")) '(("Y" . "Y (tam dung)") ("X" . "X (tam nam)")))
                         (list "jt" "Mach / khe giua cac tam (mm)" 'real0 (cond (*SD:RTJT*) (0.0)))
                         (list "ang" "Goc xoay luoi rai (do)" 'real0 (cond (*SD:RTANG*) (0.0)))
                         (list "kieu" "Kieu rai" 'kw (cond (*SD:RTKIEU*) ("Thang"))
                               '(("Thang" . "Thang hang (luoi vuong)") ("Sole" . "So le theo hang (kieu gach xay)")))
                         (list "off" "Do so le (0.5 = 1/2 tam)" 'real (cond (*SD:RTOFF*) (0.5)) nil '("kieu" "Sole"))
                         (list "chieu" "Chieu van tren vien (cat anh tam da)" 'kw (cond (*SD:ICHIEU*) ("Toiuu"))
                               '(("Toiuu" . "Tu xoay 90 do de it hao") ("Doc" . "Van theo canh dai vien") ("Ngang" . "Van vuong goc canh dai") ("Chinh" . "Van theo huong vien chinh (chon 1 vien, moi vien deu 1 huong)"))
                               '("mode" "Da"))
                         (list "xep" "Cach xep vien vao tam da (cat anh)" 'kw (cond (*SD:IXEP*) ("Toiuu"))
                               '(("Toiuu" . "It hao nhat: cat xuyen, manh nho lap vao phe lieu") ("Thutu" . "Theo thu tu lat (van gan nhau)")
                                 ("Duongviem" . "Chay doc duong vien (van lien tuc)"))
                               '("mode" "Da"))
                         (list "van" "Huong van da" 'kw (cond (*SD:RTVAN*) ("Tiepnoi"))
                               '(("Khong" . "Khong ve van") ("Tiepnoi" . "Tiep noi (cung huong)") ("Doiguong" . "Doi guong (book-match)") ("Xoay4" . "Xoay 4 chieu") ("Ngaunhien" . "Ngau nhien"))
                               '("mode" "Da"))
                         (list "vp" "Hatch van da tu file .pat" 'kw (cond (*SD:VPH2*) ("Khong"))
                               '(("Khong" . "Khong hatch (chi ve duong van)") ("Platinus" . "Platinus - nen xam sang, van toi") ("DaSocDua" . "Da Soc Dua 300x600")
                                 ("ViaLactea" . "Via Lactea - nen den") ("DaVanGoXam" . "Da Van Go Xam") ("DaVanGoCo" . "Da Van Go Co") ("Khac" . "Ten pattern khac"))
                               '("mode" "Da"))
                         (list "vpn" "Ten pattern khac (file .pat trong Support Path)" 'str "" nil '("vp" "Khac"))
                         (list "vsc" "Ti le hatch (0 = khuyen nghi theo pattern)" 'real0 0.0 nil '("mode" "Da"))
                         (list "anh" "Cat anh tam da that vao cac vien (khai bao nhu SDANHDA)" 'tog nil nil '("mode" "Da"))
                         (list "mat" "Ma vat lieu da" 'str (cond (*SD:GCODE*) ("D1")) nil '("mode" "Da"))
                         (list "name" "Ten vat lieu da" 'str (cond (*SD:GNAME*) ("Granite")) nil '("mode" "Da"))
                         (list "thk" "Chieu day da (mm)" 'real (cond (*SD:GT*) (20.0)) nil '("mode" "Da"))
                         (list "idt" "Ghi so hieu tam / vien" 'tog t)
                         (list "sc" "Ty le ve 1/" 'int (fix sc)))))
    (exit))
  (setq mode (sd:v "mode") kho (sd:v "kho") hu (sd:v "hu") jt (sd:v "jt") van (sd:v "van")
        ang (sd:v "ang") kieu (sd:v "kieu") off (sd:v "off")
        mat (sd:v "mat") name (sd:v "name") thk (sd:v "thk") idt (sd:v "idt") sc (float (sd:v "sc"))
        ianh (and (= mode "Da") (sd:v "anh"))
        fa (* pi (/ ang 180.0)) *SD:RTAOFF* ang
        *SD:RTMODE* mode *SD:RTKHO* kho *SD:RTHU* hu *SD:RTJT* jt *SD:RTVAN* van *SD:RTANG* ang *SD:RTKIEU* kieu
        *SD:ICHIEU* (cond ((sd:v "chieu")) ("Toiuu")) *SD:IXEP* (cond ((sd:v "xep")) ("Toiuu")))
  (if (> (sd:v "off") 0.0) (setq *SD:RTOFF* (sd:v "off")))
  (setq vph (if (= mode "Da") (sd:v "vp")) *SD:VPH2* vph)
  (if (equal vph "Khong") (setq vph nil))
  (if (equal vph "Khac") (setq vph (sd:v "vpn")))
  (if vph (setq vps (if (> (sd:v "vsc") 0.0) (sd:v "vsc") (cadr (sd:vp-pre vph)))))
  (if (= mode "Da") (setq *SD:GCODE* mat *SD:GNAME* name *SD:GT* thk))
  (setq stk0 (sd:rt-parse kho))
  (if (null stk0) (progn (princ "\n[SD] Kho tam sai dinh dang (VD 600x1200,400x1200:20).") (exit)))
  ;; tam tieu chuan = dien tich lon nhat, dat theo huong canh dai
  (setq std (car (sd:sort stk0 '(lambda (a b) (> (* (car a) (cadr a)) (* (car b) (cadr b))))))
        W (if (= hu "Y") (min (car std) (cadr std)) (max (car std) (cadr std)))
        H (if (= hu "Y") (max (car std) (cadr std)) (min (car std) (cadr std)))
        stk (sd:rt-orient stk0))
  (princ (strcat "\nTam tieu chuan " (sd:num W) " x " (sd:num H) " - rai tu goc (X, Y nho nhat) cua tung o"
                 (if (/= ang 0.0) (strcat ", luoi xoay " (sd:num ang) " do") "") (if (= kieu "Sole") ", so le theo hang" "") "."))
  (princ "\nChon cac polyline kin la o / phong can rai (polyline nam trong o khac = lo / cot): ")
  (if (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
    (progn
      (setq i 0)
      (repeat (sslength ss) (setq polys (cons (sd:rt-poly-of (ssname ss i)) polys) i (1+ i)))
      ;; phan loai: polyline nam trong polyline khac lon hon -> lo cua o do
      (foreach p polys
        (if (vl-some '(lambda (q) (and (not (eq (car q) (car p))) (> (caddr q) (caddr p)) (sd:inpoly (car (cadr p)) (cadr q)))) polys)
          nil
          (setq rooms (cons p rooms))))
      (setq p0 (sd:getpt "\nDiem bat dau rai tam (luoi tam di qua diem nay) <goc X, Y nho nhat cua o>: " nil))
      (if (= mode "Panel") (setq pt (sd:getpt "\nDiem chen bang thong ke <bo qua>: " nil)))
      (setq used nil bom nil nroom 0 nfull 0 ncut 0 ntim 0 atim 0.0)
      (foreach room (reverse rooms)
        (setq nroom (1+ nroom) outer (cadr room) holes nil)
        (foreach p polys
          (if (and (not (eq (car p) (car room))) (< (caddr p) (caddr room)) (sd:inpoly (car (cadr p)) outer))
            (setq holes (cons p holes))))
        (setq lps (mapcar 'cadr holes) loops (cons outer lps) edges (sd:edges loops)
              R (sd:region (car room)))
        (if (null R)
          (princ (strcat "\n[SD] O " (itoa nroom) ": khong tao duoc region (polyline tu cat nhau?), bo qua."))
          (progn
            (foreach hp holes (if (setq tr (sd:region (car hp))) (vla-Boolean R 2 tr)))
            ;; khung toa do cuc bo xoay goc fa quanh goc bbox; luoi rai bat dau tu goc X, Y nho nhat trong khung do
            (setq bb (sd:bbox outer) fo (if p0 (list (car p0) (cadr p0)) (list (caar bb) (cadar bb)))
                  x0 (car fo) y0 (cadr fo)
                  lo (mapcar '(lambda (q) (sd:w2l fo fa q)) outer)
                  lb (sd:bbox lo) lx0 (caar lb) ly0 (cadar lb) lx1 (car (cadr lb)) ly1 (cadr (cadr lb))
                  px (+ W jt) py (+ H jt))
            ;; co diem bat dau: luoi tam di qua diem do (can ve o luoi gan nhat phia duoi-trai bbox)
            (if p0
              (setq lx0 (* px (- (fix (/ lx0 px)) 1)) ly0 (* py (- (fix (/ ly0 py)) 1))))
            (setq nx (+ 3 (fix (/ (- lx1 lx0) px))) ny (+ 2 (fix (/ (- ly1 ly0) py))) seq 0 pieces nil cj 0)
            (repeat ny
              (setq ci 0 shf (if (= kieu "Sole") (* px (rem (* cj off) 1.0)) 0.0))
              (repeat nx
                (setq ii (if (= (rem cj 2) 0) ci (- nx 1 ci))
                      cx (+ lx0 (if (> shf 1e-6) (- shf px) 0.0) (* ii px)) cy (+ ly0 (* cj py))
                      lcs (list (list cx cy) (list (+ cx W) cy) (list (+ cx W) (+ cy H)) (list cx (+ cy H)))
                      cs (mapcar '(lambda (q) (sd:l2w fo fa q)) lcs)
                      cls (sd:tile-class cs outer lps loops edges) cl nil)
                (if (= cls "P")
                  (progn
                    (setq cl (sd:rt-clip R cs (if (= mode "Da") "SD-GACH-CAT" "INFILL-TIMBER")))
                    (cond ((null cl) (setq cls nil))
                          ((>= (car cl) (* 0.99999 W H)) (foreach x (cadr cl) (entdel x)) (setq cls "F" cl nil)))))
                (cond
                  ;; ---- vien nguyen
                  ((= cls "F")
                   (setq seq (1+ seq))
                   (if (= mode "Panel")
                     (progn
                       (setq fit (sd:rt-fit W H stk used) used (caddr fit))
                       (sd:rt-put-panels (car fit) cx cy stk0 sc idt fo fa)
                       (foreach p (car fit) (setq bom (sd:al-add bom (sd:rt-code (caddr p) (cadddr p)) 1) nfull (1+ nfull)))
                       (sd:rt-put-timber (cadr fit) cx cy sc fo fa)
                       (foreach p (cadr fit) (setq ntim (1+ ntim) atim (+ atim (* (caddr p) (cadddr p))) bom (sd:al-add bom "GO-BU" 1))))
                     (progn
                       (sd:mk-tile-poly "SD-GACH" cs
                                      (sd:tile-xd mat "F" mat W H (* W H) 0 name W H fa thk "R"))
                       (setq nfull (1+ nfull) pe (entlast) vd (sd:rt-vein van ii cj))
                       (if vph (sd:rt-vh (list pe) vph vps van vd (car (car cs)) (cadr (car cs)) x0 y0)
                         (if vd (sd:pline (mapcar '(lambda (q) (sd:l2w fo fa q)) (sd:rt-vpts vd cx cy W H)) nil "SD-GACH-VAN")))
                       (if idt (sd:text (sd:l2w fo fa (list (+ cx (/ W 2.0)) (+ cy (/ H 2.0)))) (strcat (itoa nroom) "." (itoa seq))
                                        (sd:tile-th W H sc) "MC" "SD-CHU")))))
                  ;; ---- o bi cat boi bien / lo
                  ((and cl (= cls "P"))
                   (setq vp (caddr cl) lvp (mapcar '(lambda (q) (sd:w2l fo fa q)) vp)
                         gx (apply 'min (mapcar 'car lvp)) gy (apply 'min (mapcar 'cadr lvp))
                         gw (- (apply 'max (mapcar 'car lvp)) gx) gh (- (apply 'max (mapcar 'cadr lvp)) gy)
                         wg (sd:l2w fo fa (list gx gy)))
                   (if (>= (car cl) (* 0.999999 gw gh))
                     (progn
                       ;; phan thieu hut hinh chu nhat (trong khung xoay)
                       (foreach x (cadr cl) (entdel x))
                       (if (= mode "Panel")
                         (progn
                           (setq fit (sd:rt-fit gw gh stk used) used (caddr fit))
                           (sd:rt-put-panels (car fit) gx gy stk0 sc idt fo fa)
                           (foreach p (car fit) (setq bom (sd:al-add bom (sd:rt-code (caddr p) (cadddr p)) 1) nfull (1+ nfull)))
                           (sd:rt-put-timber (cadr fit) gx gy sc fo fa)
                           (foreach p (cadr fit) (setq ntim (1+ ntim) atim (+ atim (* (caddr p) (cadddr p))) bom (sd:al-add bom "GO-BU" 1))))
                         (progn
                           (sd:pline (mapcar '(lambda (q) (sd:l2w fo fa q))
                                             (list (list gx gy) (list (+ gx gw) gy) (list (+ gx gw) (+ gy gh)) (list gx (+ gy gh))))
                                     t "SD-GACH-CAT")
                           (setq pe (entlast))
                           (if vph (sd:rt-vh (list pe) vph vps van (sd:rt-vein van ii cj) (car wg) (cadr wg) x0 y0))
                           (setq seq (1+ seq)
                                 pieces (cons (list (list pe) gw gh (car cl) (sd:rect-typ gw gh (car cl) nil)
                                                    (sd:centroid vp) (list gx gy) (list 0.0 0.0 0.0) fa) pieces)))))
                     ;; hinh bat ky (cat boi duong cheo / lo): khong rai tam duoc
                     (progn
                       (setq seq (1+ seq))
                       (if (= mode "Panel")
                         (progn (setq ntim (1+ ntim) atim (+ atim (car cl)) bom (sd:al-add bom "GO-BU" 1))
                                (sd:text (sd:centroid vp) "GO" (* 1.6 sc) "MC" "SD-CHU"))
                         (progn (if vph (sd:rt-vh (cadr cl) vph vps van (sd:rt-vein van ii cj) (car wg) (cadr wg) x0 y0))
                                (setq pieces (cons (list (cadr cl) gw gh (car cl) "D" (sd:centroid vp) (list gx gy) (list 0.0 0.0 0.0) fa) pieces))))))))
                (setq ci (1+ ci)))
              (setq cj (1+ cj)))
            (if (and (= mode "Da") pieces)
              (progn (setq rc (sd:code-pieces (reverse pieces) mat name W H thk nil sc))
                     (setq ncut (+ ncut (length pieces)))))
            (vla-Delete R))))
      (if (= mode "Panel")
        (progn
          (princ (strcat "\n[SD] " (itoa nroom) " o: " (itoa nfull) " tam (" (itoa (length (vl-remove "GO-BU" (mapcar 'car bom)))) " loai); go bu "
                         (itoa ntim) " manh, " (sd:rtos (/ atim 1e6) 2) " m2 (layer INFILL-TIMBER)."))
          (if (and pt bom)
            (progn
              (setq bom (sd:al-sorted bom) rows nil n 0)
              (foreach b bom
                (setq n (1+ n)
                      rows (cons (list "R" (list (itoa n) (car b) (if (= (car b) "GO-BU") "Go bu mep bien (INFILL-TIMBER)" "Tam rai theo kho") (itoa (cdr b))) nil) rows)))
              (sd:table2 pt "THONG KE RAI TAM" '(("STT" 10) ("MA TAM" 34) ("LOAI" 52) ("SL" 14)) (reverse rows) -1 sc)
              (if (setq f (sd:open (setq fn (sd:csv-name "_RaiTam.csv")) "w"))
                (progn (write-line "STT,Ma tam,Loai,So luong" f)
                       (foreach rw rows (write-line (sd:join (cadr rw) ",") f))
                       (princ (strcat "\n[SD] Da xuat: " (sd:close f))))))))
        (princ (strcat "\n[SD] " (itoa nroom) " o: " (itoa nfull) " vien nguyen, " (itoa ncut) " vien cat"
                       ". Dung SDGACHTK / SDTKDA de thong ke, SDDATHO cat tu da tho, SDGIACONG ve gia cong.")))
      (setq *SD:RTAOFF* 0.0)
      (if ianh (progn (setq *SD:IFRAME* (if (>= W H) fa (+ fa (/ pi 2.0)))) (sd:anhda (sd:gach-new e0)) (setq *SD:IFRAME* nil))))
    (princ "\n[SD] Chua chon o nao."))
  (setq *SD:RTAOFF* 0.0)
  (sd:finish))

;; 4 dinh (toa do that) cua hinh chu nhat trong khung cuc bo (fo, fa): goc (ox + x, oy + y), rong w, cao h
(defun sd:rt-lw (fo fa ox oy x y w h)
  (mapcar '(lambda (p) (sd:l2w fo fa p))
          (list (list (+ ox x) (+ oy y)) (list (+ ox x w) (+ oy y)) (list (+ ox x w) (+ oy y h)) (list (+ ox x) (+ oy y h)))))

;; Ve tam (x y rong cao tuong doi goc ox oy trong khung cuc bo)
(defun sd:rt-put-panels (pan ox oy stk0 sc idt fo fa / code)
  (foreach p pan
    (setq code (sd:rt-code (caddr p) (cadddr p)))
    (sd:pline (sd:rt-lw fo fa ox oy (car p) (cadr p) (caddr p) (cadddr p)) t "SD-PANEL")
    (sd:col-last (sd:rt-color code stk0))
    (if idt (sd:text (sd:l2w fo fa (list (+ ox (car p) (/ (caddr p) 2.0)) (+ oy (cadr p) (/ (cadddr p) 2.0))))
                     (sd:num (min (caddr p) (cadddr p))) (sd:tile-th (caddr p) (cadddr p) sc) "MC" "SD-CHU"))))

;; Ve go bu: khung + duong cheo tren layer INFILL-TIMBER
(defun sd:rt-put-timber (tim ox oy sc fo fa)
  (foreach p tim
    (sd:pline (sd:rt-lw fo fa ox oy (car p) (cadr p) (caddr p) (cadddr p)) t "INFILL-TIMBER")
    (sd:line (sd:l2w fo fa (list (+ ox (car p)) (+ oy (cadr p))))
             (sd:l2w fo fa (list (+ ox (car p) (caddr p)) (+ oy (cadr p) (cadddr p)))) "INFILL-TIMBER")))

(defun sd:jesc (s / r c)
  (setq r "")
  (foreach ch (vl-string->list s)
    (setq c (cond ((= ch 92) "\\\\") ((= ch 34) "\\\"") ((< ch 32) " ") (t (chr ch))))
    (setq r (strcat r c)))
  r)

;;; --------------------------------------------------------------------------
;;;  SDQUYTRINH - Hop thoai DCL thong minh: quy trinh da lat, ra lenh lien hoan
;;;  Doc trang thai ban ve (so vien, anh tam da, anh da cat, hatch van), goi y buoc tiep theo, chay tung buoc hoac
;;;  chay lien hoan cac buoc da chon; sau moi buoc quay lai hop thoai.
;;; --------------------------------------------------------------------------
(setq *SD:QTSTEPS*
  '(("SDRAITAM" "Chia vien / rai tam theo kho (Panel hoac Da, vien cat mep, go bu)" "Chon Da: vien nguyen + vien cat, so hieu theo thu tu lat. Panel: tam tieu chuan + tam di hinh + go bu.")
    ("SDGACH"   "Chia vien op lat cho 1 vung (thang / so le / xuong ca / chevron, vien vien)" "Dung khi chi can 1 vung, hoac can kieu lat xuong ca / chevron.")
    ("SDDOCDA"  "Doc mat bang op lat (net roi) -> dung o kin, bang CSV / JSON, ma vat lieu, khoet lo / cot, ve polyline" "Quet chon net mat bang; soat bang trong Excel; Ve de tao polyline kin roi SDANHDA (khong can ve lai polyline).")
    ("SDANHDA"  "Cat anh tam da tho vao cac vien (IMAGECLIP, xep cat xuyen, thu tu cat)" "Chen anh tam da (IMAGEATTACH) truoc. Quet chon polyline vien; chon chieu van va cach xep.")
    ("SDVANDA"  "Hatch van da tu file .pat len vien (khi khong co anh that)" "Chon pattern Platinus / DaSocDua / ViaLactea / DaVanGoXam / DaVanGoCo; Tiepnoi de van chay lien tuc.")
    ("SDGACHTK" "Thong ke vien + du tru so vien dat hang" "Bang ma vien, loai, kich thuoc, so luong, dien tich + dong dat hang.")
    ("SDDATHO"  "So do cat vien tu da tho (kho tam, hao phi)" "Dung khi mua da tho: tinh so tam va ve so do cat.")
    ("SDGIACONG" "Ban ve gia cong tung ma vien gui xuong" "Moi ma vien mot the gia cong kem kich thuoc.")
    ("SDTKDA"   "Quet polyline vien da cat -> bang thong ke nhom kich thuoc + chi tiet tung vien" "Bang ma V1..., kich thuoc, SL, dien tich, canh mai; chi tiet tung vien kem ma T.. va tam da so (sau SDANHDA).")
    ("SDDOCDATK" "Thong ke vien da sau SDDOCDA kieu SDGACHTK: bang nhom kich thuoc + dat tam da" "Nhap kho tam da, hao hut %; bang V1.. + dong dat hang + CSV.")
    ("SDANHDATK" "Thong ke tam da sau SDANHDA kieu SDGACHTK: so vien, hao hut tung tam + dat tam" "Nhap kho tam da, hao hut %; bang theo tam da so + dong dat hang + CSV.")
    ("SDKTLAT" "Kiem tra ban ve lat (chi doc): vien cat hep / nho, ron khong deu, o thieu ma vat lieu" "Khoanh do cho co van de tren layer SD-KIEMTRA, xuat CSV.")))

(defun sd:qt-cnt (flt / ss) (if (setq ss (ssget "_X" flt)) (sslength ss) 0))
;; Trang thai ban ve: (so-vien so-anh-tam so-anh-da-cat so-hatch-van)
(defun sd:qt-state ()
  (list (sd:qt-cnt '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT,SD-GACH-DOC")))
        (sd:qt-cnt '((0 . "IMAGE")))
        (sd:qt-cnt '((8 . "SD-GACH-ANH")))
        (sd:qt-cnt '((0 . "HATCH") (8 . "SD-GACH-VAN")))))
;; Buoc goi y tiep theo (chi so trong *SD:QTSTEPS*)
(defun sd:qt-next (st)
  (cond ((= (car st) 0) 0)
        ((and (> (cadr st) 0) (= (caddr st) 0)) 3)
        ((and (= (caddr st) 0) (= (cadddr st) 0)) 4)
        (t 5)))

(defun sd:qt-run (cmd / r)
  (princ (strcat "\n[SD] === Chay " cmd " ==="))
  (setq r (vl-catch-all-apply '(lambda () (apply (read (strcat "c:" cmd)) nil)) nil))
  (if (vl-catch-all-error-p r) (princ (strcat "\n[SD] " cmd " dung: " (vl-catch-all-error-message r)))))

(defun sd:qt-dcl (fn / f)
  (if (setq f (open fn "w"))
    (progn
      (foreach l '("sdqt : dialog { label = \"Quy trinh da lat - ra lenh lien hoan (SDQUYTRINH)\";"
                   "  : text { key = \"info\"; width = 84; }"
                   "  : list_box { key = \"lst\"; multiple_select = true; width = 84; height = 10; allow_accept = false; }"
                   "  : text { key = \"hint\"; width = 84; }"
                   "  : text { label = \"Chon 1 buoc de chay, hoac tich nhieu buoc (Ctrl / Shift) roi bam Chay lien hoan.\"; }"
                   "  : row {"
                   "    : button { key = \"run\"; label = \"Chay buoc chon\"; width = 20; is_default = true; }"
                   "    : button { key = \"chain\"; label = \"Chay lien hoan\"; width = 20; }"
                   "    : button { key = \"help\"; label = \"Huong dan\"; width = 14; }"
                   "    : cancel_button { label = \"Dong\"; width = 12; }"
                   "  }"
                   "}")
        (write-line l f))
      (close f)
      fn)))

(defun sd:qt-idx (s / r)
  (foreach x (sd:split (vl-string-trim " " s) " ") (if (/= x "") (setq r (cons (atoi x) r))))
  (reverse r))

(defun c:SDQUYTRINH (/ fn id res st rec sel more idxs)
  (setq fn (vl-filename-mktemp "sdqt" nil ".dcl") more t sel nil)
  (if (not (sd:qt-dcl fn))
    (princ "\n[SD] Khong tao duoc hop thoai (DCL). Chay lan luot: SDRAITAM, SDANHDA, SDVANDA, SDGACHTK.")
    (while more
      (setq st (sd:qt-state) rec (sd:qt-next st))
      (if (and (setq id (load_dialog fn)) (> id 0) (new_dialog "sdqt" id))
        (progn
          (set_tile "info" (strcat "Hien co: " (itoa (car st)) " vien | " (itoa (cadr st)) " anh | " (itoa (caddr st)) " anh da cat | "
                                   (itoa (cadddr st)) " hatch van.   Goi y: " (car (nth rec *SD:QTSTEPS*))))
          (start_list "lst")
          (setq idxs 0)
          (foreach s *SD:QTSTEPS*
            (add_list (strcat (itoa (1+ idxs)) ".  " (sd:pad (car s) 11) (cadr s) (if (= idxs rec) "   <== goi y" "")))
            (setq idxs (1+ idxs)))
          (end_list)
          (set_tile "lst" (cond (sel) ((itoa rec))))
          (set_tile "hint" (caddr (nth rec *SD:QTSTEPS*)))
          (action_tile "lst" "(setq *SD:QTSEL* $value) (set_tile \"hint\" (caddr (nth (car (sd:qt-idx $value)) *SD:QTSTEPS*)))")
          (action_tile "run" "(setq *SD:QTSEL* (get_tile \"lst\")) (done_dialog 2)")
          (action_tile "chain" "(setq *SD:QTSEL* (get_tile \"lst\")) (done_dialog 3)")
          (action_tile "help" "(alert (strcat \"QUY TRINH DA LAT:\\n1. SDRAITAM / SDGACH: chia vien tren cac vung.\\n2. SDANHDA: chen anh tam da roi cat anh vao vien (hoac SDVANDA hatch van).\\n3. SDGACHTK / SDDATHO / SDGIACONG: thong ke, so do cat, ban ve gia cong.\\n4. SDKTLAT: kiem tra truoc khi phat hanh.\\nXem them HuongDanQuyTrinhDa.md trong thu muc cai dat.\"))")
          (action_tile "cancel" "(done_dialog 0)")
          (setq res (start_dialog))
          (unload_dialog id)
          (cond
            ((member res '(2 3))
             (setq sel *SD:QTSEL* idxs (sd:qt-idx (cond (sel) ("")))
                   idxs (if (= res 2) (list (cond ((car idxs)) (rec))) (if idxs idxs (list rec))))
             (foreach i idxs (sd:qt-run (car (nth i *SD:QTSTEPS*)))))
            (t (setq more nil))))
        (progn (princ "\n[SD] Khong mo duoc hop thoai.") (setq more nil)))))
  (vl-file-delete fn)
  (princ))

;;; --------------------------------------------------------------------------
;;;  SDTKDA - Quet polyline vien da cat -> bang thong ke (nhom theo kich thuoc, chi tiet tung vien, tam da, CSV)
;;;  Doc truc tiep hinh hoc polyline (khong can du lieu SD_TILE): kich thuoc theo canh dai nhat, dien tich, chu vi (canh mai),
;;;  hinh dang (chu nhat / da giac vat); neu da chay SDANHDA thi them cot ma vien T.. va tam da so.
;;; --------------------------------------------------------------------------
(defun sd:tk-meas (e / pts fr ar pe lg sh)
  (setq pts (sd:curve-pts e) fr (sd:tile-frame pts) ar (abs (sd:area pts))
        pe (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e))
        lg (max (cadr fr) (caddr fr)) sh (min (cadr fr) (caddr fr)))
  ;; (dai rong dien-tich chu-vi hinh tam-vien)
  (list lg sh ar pe (if (< (abs (- ar (* lg sh))) (* 0.005 lg sh)) "CN" "DG") (cadddr fr)))

;; Tim thong tin SDANHDA (ma vien, tam) theo tam vien gan nhat (sai so 2 mm)
(defun sd:tk-link (cw lk / r)
  (foreach x lk
    (if (and (null r) (< (distance cw (list (cadr x) (caddr x))) 2.0)) (setq r x)))
  r)

(defun sd:tk-key (m tol) (list (fix (+ 0.5 (/ (car m) tol))) (fix (+ 0.5 (/ (cadr m) tol))) (nth 4 m) (nth 7 m)))

;; Hatch trong ban ve: ((min max dien-tich-bbox loai) ...); loai = ten pattern, hatch SOLID thi M<mau> hoac ten layer
(defun sd:tk-hatches (/ ss i e ed bb r ty)
  (if (setq ss (ssget "_X" '((0 . "HATCH"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) ed (entget e))
        (if (setq bb (sd:nb-bbox (list e)))
          (setq ty (if (/= (strcase (cdr (assoc 2 ed))) "SOLID") (cdr (assoc 2 ed))
                     (if (assoc 62 ed) (strcat "M" (itoa (cdr (assoc 62 ed)))) (cdr (assoc 8 ed))))
                r (cons (list (car bb) (cadr bb) (* (- (car (cadr bb)) (car (car bb))) (- (cadr (cadr bb)) (cadr (car bb)))) ty
                              (/= (strcase (cdr (assoc 2 ed))) "SOLID"))
                        r))))))
  r)
;; Loai hatch tai diem c: uu tien hatch co pattern (khong SOLID), roi hatch nho nhat chua diem; nhieu hatch chong nhau chi tinh 1 loai
(defun sd:tk-htype (c hl / best)
  (foreach h hl
    (if (and (>= (car c) (car (car h))) (<= (car c) (car (cadr h))) (>= (cadr c) (cadr (car h))) (<= (cadr c) (cadr (cadr h))))
      (if (or (null best)
              (and (nth 4 h) (not (nth 4 best)))
              (and (eq (nth 4 h) (nth 4 best)) (< (caddr h) (caddr best))))
        (setq best h))))
  (if best (nth 3 best) "-"))

(defun c:SDTKDA (/ ss i e ms tol nm g grp key o rows drows ti dt lk tot ar pe n pt sc fn f lines k lkx tam mm hl seen cell dup)
  (sd:begin)
  (setq sc (sd:sc))
  (if (not (sd:dlg "Thong ke vien da cat (SDTKDA)"
                   (list (list "pv" "Pham vi" 'kw (cond (*SD:TKDPV*) ("Chon"))
                               '(("Chon" . "Quet chon cac polyline vien da") ("Tatca" . "Tat ca polyline kin tren layer SD-GACH / SD-GACH-CAT / SD-GACH-VIEN / SD-GACH-DOC")))
                         (list "tol" "Dung sai gom nhom kich thuoc (mm)" 'real (cond (*SD:TKDTOL*) (2.0)))
                         (list "ht" "Chia theo loai hatch da (pattern / mau)" 'tog t)
                         (list "dd" "Bo vien chong len nhau (trung tam, trung dien tich)" 'tog t)
                         (list "ct" "Them bang chi tiet tung vien (ma, tam da)" 'tog t)
                         (list "csv" "Xuat file CSV canh file ban ve" 'tog t))))
    (exit))
  (setq tol (max 0.5 (sd:v "tol")) *SD:TKDTOL* tol *SD:TKDPV* (sd:v "pv"))
  (setq ss (if (= (sd:v "pv") "Tatca")
             (ssget "_X" '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT,SD-GACH-VIEN,SD-GACH-DOC") (-4 . "&") (70 . 1)))
             (progn (princ "\nQuet chon cac polyline kin la vien da: ") (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))))
  (if (null ss)
    (princ "\n[SD] Khong co polyline vien nao.")
    (progn
      (setq lk (vlax-ldata-get "SD" "ANHDA") i 0 dup 0)
      (if (sd:v "ht") (setq hl (sd:tk-hatches)))
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) ms (sd:tk-meas e)
              ms (append ms (list (sd:tk-link (nth 5 ms) lk) (if (sd:v "ht") (sd:tk-htype (nth 5 ms) hl) "-"))))
        ;; vien chong len nhau: cung tam (sai so ~2 mm), dien tich lech < 0.5% -> chi tinh 1 lan
        (setq cell (list (fix (/ (car (nth 5 ms)) 4.0)) (fix (/ (cadr (nth 5 ms)) 4.0))) o nil)
        (if (sd:v "dd")
          (progn
            (foreach x (cdr (assoc cell seen))
              (if (and (< (distance (car x) (nth 5 ms)) 2.0) (< (abs (- (cadr x) (caddr ms))) (* 0.005 (caddr ms)))) (setq o t)))
            (if o (setq dup (1+ dup))
              (setq seen (if (assoc cell seen)
                           (subst (cons cell (cons (list (nth 5 ms) (caddr ms)) (cdr (assoc cell seen)))) (assoc cell seen) seen)
                           (cons (list cell (list (nth 5 ms) (caddr ms))) seen))))))
        (if (not o)
          (progn
            (setq key (sd:tk-key ms tol))
            (if (setq g (assoc key grp))
              (setq grp (subst (append g (list ms)) g grp))
              (setq grp (cons (list key ms) grp))))))
      (if (> dup 0) (princ (strcat "\n[SD] Bo " (itoa dup) " polyline chong len nhau (trung vi tri va dien tich).")))
      ;; nhom: dien tich 1 vien giam dan -> ma V1, V2...
      (setq grp (sd:sort grp '(lambda (a b) (> (* (car (cadr a)) (cadr (cadr a))) (* (car (cadr b)) (cadr (cadr b)))))) n 0 tot (list 0 0.0 0.0) rows nil)
      (foreach g grp
        (setq n (1+ n) o (cadr g)
              ar (/ (apply '+ (mapcar 'caddr (cdr g))) (length (cdr g))) pe (/ (apply '+ (mapcar 'cadddr (cdr g))) (length (cdr g))))
        (setq rows (cons (list "R" (list (strcat "V" (itoa n))
                                         (strcat (sd:rtos (car o) 0) " x " (sd:rtos (cadr o) 0))
                                         (if (= (nth 4 o) "CN") "Chu nhat" "Vat / da giac")
                                         (nth 7 o)
                                         (itoa (length (cdr g)))
                                         (sd:rtos (/ ar 1e6) 3)
                                         (sd:rtos (/ (* ar (length (cdr g))) 1e6) 2)
                                         (sd:rtos (/ (* pe (length (cdr g))) 1000.0) 1))
                               nil)
                         rows))
        (setq tot (list (+ (car tot) (length (cdr g))) (+ (cadr tot) (* ar (length (cdr g)))) (+ (caddr tot) (* pe (length (cdr g)))))))
      (setq rows (append (reverse rows)
                         (list (list "S" (strcat "TONG CONG: " (itoa (car tot)) " vien, " (itoa (length grp)) " nhom kich thuoc")
                                     (strcat (sd:rtos (/ (cadr tot) 1e6) 2) " m2 - canh mai " (sd:rtos (/ (caddr tot) 1000.0) 1) " m")))))
      (princ (strcat "\n[SD] " (itoa (car tot)) " vien, " (itoa (length grp)) " nhom kich thuoc, tong " (sd:rtos (/ (cadr tot) 1e6) 2) " m2, canh mai "
                     (sd:rtos (/ (caddr tot) 1000.0) 1) " m."))
      (foreach r (vl-remove-if-not '(lambda (x) (= (car x) "R")) rows)
        (princ (strcat "\n  " (nth 0 (cadr r)) "  " (nth 1 (cadr r)) "  x" (nth 4 (cadr r)) "  (" (nth 2 (cadr r)) ", hatch " (nth 3 (cadr r)) ")")))
      ;; chi tiet tung vien
      (if (sd:v "ct")
        (progn
          (setq ti 0)
          (foreach g grp
            (foreach m (cdr g)
              (setq ti (1+ ti) lkx (nth 6 m))
              (setq drows (cons (list "R" (list (if lkx (car lkx) (itoa ti))
                                                (strcat "V" (itoa (1+ (vl-position g grp))))
                                                (strcat (sd:rtos (car m) 0) " x " (sd:rtos (cadr m) 0))
                                                (sd:rtos (/ (caddr m) 1e6) 3)
                                                (if (and lkx (nth 3 lkx)) (itoa (1+ (nth 3 lkx))) "-"))
                                      nil)
                                drows)))))
        )
      (if (setq pt (sd:getpt "\nDiem chen bang thong ke <bo qua>: " nil))
        (progn
          (sd:table2 pt "BANG THONG KE VIEN DA CAT"
                     '(("MA" 14) ("KICH THUOC (mm)" 34) ("HINH DANG" 28) ("LOAI HATCH" 26) ("SL" 12) ("DT 1 VIEN (m2)" 24) ("TONG DT (m2)" 24) ("CANH MAI (m)" 24))
                     rows -1 sc)
          (if (and (sd:v "ct") drows)
            (sd:table2 (sd:p+ pt 0 (* -10.0 sc (+ 4 (length rows))))
                       "CHI TIET TUNG VIEN"
                       '(("VIEN" 18) ("NHOM" 16) ("KICH THUOC (mm)" 34) ("DT (m2)" 22) ("TAM DA" 18))
                       (sd:sort (reverse drows) '(lambda (a b) (sd:fl< (car (cadr a)) (car (cadr b))))) -1 sc))))
      (if (sd:v "csv")
        (if (setq f (sd:open (setq fn (sd:csv-name "_ThongKeDa.csv")) "w"))
          (progn
            (write-line "Ma,Kich thuoc dai,Kich thuoc rong,Hinh dang,Loai hatch,So luong,Dien tich 1 vien m2,Tong dien tich m2,Canh mai m" f)
            (foreach g grp
              (setq o (cadr g) n (length (cdr g))
                    ar (/ (apply '+ (mapcar 'caddr (cdr g))) n) pe (/ (apply '+ (mapcar 'cadddr (cdr g))) n))
              (write-line (sd:join (list (strcat "V" (itoa (1+ (vl-position g grp)))) (sd:rtos (car o) 0) (sd:rtos (cadr o) 0)
                                         (nth 4 o) (nth 7 o) (itoa n) (sd:rtos (/ ar 1e6) 3) (sd:rtos (/ (* ar n) 1e6) 2) (sd:rtos (/ (* pe n) 1000.0) 1)) ",") f))
            (princ (strcat "\n[SD] Da xuat: " (sd:close f))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDDOCDATK / SDANHDATK - Thong ke da kieu SDGACHTK: bang + du tru dat tam da + CSV
;;;  SDDOCDATK: theo nhom kich thuoc (viec sau SDDOCDA); SDANHDATK: theo tung tam da (sau SDANHDA)
;;;  Doc truc tiep hinh hoc polyline nen khong can du lieu SD_TILE.
;;; --------------------------------------------------------------------------
(defun sd:tkx (che / ss i e ms tol grp key g n sw sh loss ar tot rows lk lkx pt sc fn f slabs sl used ord nsl tarea)
  (setq sc (sd:sc))
  (if (not (sd:dlg (if (= che "ANH") "Thong ke tam da sau SDANHDA (SDANHDATK)" "Thong ke vien da sau SDDOCDA (SDDOCDATK)")
                   (list (list "sw" "Tam da: dai (mm)" 'real (cond (*SD:TKXW*) (2450.0)))
                         (list "sh" "Tam da: rong (mm)" 'real (cond (*SD:TKXH*) (1170.0)))
                         (list "loss" "Hao hut van chuyen / vo (%)" 'real0 (cond (*SD:TKXL*) (3.0)))
                         (list "tol" "Dung sai gom nhom kich thuoc (mm)" 'real (cond (*SD:TKDTOL*) (2.0))))))
    (exit))
  (setq sw (sd:v "sw") sh (sd:v "sh") loss (sd:v "loss") tol (max 0.5 (sd:v "tol"))
        *SD:TKXW* sw *SD:TKXH* sh *SD:TKXL* loss *SD:TKDTOL* tol)
  (princ "\nChon cac polyline vien da <Enter = tat ca tren layer SD-GACH / SD-GACH-CAT / SD-GACH-VIEN / SD-GACH-DOC>: ")
  (setq ss (cond ((ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))
                 ((ssget "_X" '((0 . "LWPOLYLINE") (8 . "SD-GACH,SD-GACH-CAT,SD-GACH-VIEN,SD-GACH-DOC") (-4 . "&") (70 . 1))))))
  (if (null ss)
    (princ "\n[SD] Khong co polyline vien nao.")
    (progn
      (setq lk (vlax-ldata-get "SD" "ANHDA") i 0 tot 0.0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) ms (sd:tk-meas e)
              ms (append ms (list (sd:tk-link (nth 5 ms) lk)))
              tot (+ tot (caddr ms)))
        (setq key (if (= che "ANH") (list (cond ((and (nth 6 ms) (nth 3 (nth 6 ms))) (nth 3 (nth 6 ms))) (-1))) (sd:tk-key ms tol)))
        (if (setq g (assoc key grp))
          (setq grp (subst (append g (list ms)) g grp))
          (setq grp (cons (list key ms) grp))))
      (setq n 0)
      (if (= che "ANH")
        (progn
          (setq grp (sd:sort grp '(lambda (a b) (< (car (car a)) (car (car b))))) used 0)
          (foreach g grp
            (setq ar (apply '+ (mapcar 'caddr (cdr g))))
            (if (>= (car (car g)) 0) (setq used (1+ used)))
            (setq rows (cons (list "R" (list (if (>= (car (car g)) 0) (itoa (1+ (car (car g)))) "chua gan")
                                             (itoa (length (cdr g)))
                                             (sd:rtos (/ ar 1e6) 2)
                                             (if (>= (car (car g)) 0) (strcat (sd:rtos (* 100.0 (- 1.0 (/ ar (* sw sh)))) 1) " %") "-"))
                                   nil)
                             rows)))
          (setq nsl used ord (fix (+ (* nsl (+ 1.0 (/ loss 100.0))) 0.999999))
                rows (append (reverse rows)
                             (list (list "S" (strcat "TONG: " (itoa (sslength ss)) " vien, " (itoa nsl) " tam da dung") (strcat (sd:rtos (/ tot 1e6) 2) " m2"))
                                   (list "W" (strcat "   Dat hang tam " (sd:num sw) "x" (sd:num sh) ": " (itoa nsl) " + hao hut " (sd:num loss) "% = " (itoa ord) " tam"))))))
        (progn
          (setq grp (sd:sort grp '(lambda (a b) (> (* (car (cadr a)) (cadr (cadr a))) (* (car (cadr b)) (cadr (cadr b)))))))
          (foreach g grp
            (setq n (1+ n) e (cadr g) ar (/ (apply '+ (mapcar 'caddr (cdr g))) (length (cdr g))))
            (setq rows (cons (list "R" (list (strcat "V" (itoa n)) (strcat (sd:rtos (car e) 0) " x " (sd:rtos (cadr e) 0))
                                             (itoa (length (cdr g))) (sd:rtos (/ ar 1e6) 3)
                                             (sd:rtos (/ (* ar (length (cdr g))) 1e6) 2))
                                   nil)
                             rows)))
          (setq nsl (fix (+ (/ tot (* sw sh)) 0.999999)) ord (fix (+ (* (/ tot (* sw sh)) (+ 1.0 (/ loss 100.0))) 0.999999))
                rows (append (reverse rows)
                             (list (list "S" (strcat "TONG: " (itoa (sslength ss)) " vien, " (itoa (length grp)) " nhom") (strcat (sd:rtos (/ tot 1e6) 2) " m2"))
                                   (list "W" (strcat "   Dat hang tam " (sd:num sw) "x" (sd:num sh) ": " (sd:rtos (/ tot (* sw sh)) 2) " tam + hao hut " (sd:num loss) "% = " (itoa ord) " tam (uoc tinh theo dien tich, chua tinh xep cat)")))))))
      (princ (strcat "\n[SD] " (itoa (sslength ss)) " vien, " (sd:rtos (/ tot 1e6) 2) " m2 -> dat " (itoa ord) " tam "
                     (sd:num sw) "x" (sd:num sh) " (da gom hao hut " (sd:num loss) "%)."))
      (if (setq pt (sd:getpt "\nDiem chen bang thong ke <bo qua>: " nil))
        (if (= che "ANH")
          (sd:table2 pt "BANG THONG KE TAM DA" '(("TAM DA SO" 24) ("SO VIEN" 18) ("DT VIEN (m2)" 24) ("HAO HUT TAM" 26)) rows -1 sc)
          (sd:table2 pt "BANG THONG KE VIEN DA" '(("MA" 14) ("KICH THUOC (mm)" 34) ("SL" 12) ("DT 1 VIEN (m2)" 24) ("TONG DT (m2)" 24)) rows -1 sc)))
      (if (setq f (sd:open (setq fn (sd:csv-name (if (= che "ANH") "_ThongKeTamDa.csv" "_ThongKeVienDa.csv"))) "w"))
        (progn
          (write-line (if (= che "ANH") "Tam da so;So vien;DT vien m2;Hao hut tam %" "Ma;Dai;Rong;SL;DT 1 vien m2;Tong DT m2") f)
          (foreach r (vl-remove-if-not '(lambda (x) (= (car x) "R")) rows) (write-line (sd:join (cadr r) ";") f))
          (write-line (strcat "Dat hang;" (itoa ord) ";tam " (sd:num sw) "x" (sd:num sh)) f)
          (princ (strcat "\n[SD] Da xuat: " (sd:close f)))))))
  (sd:finish))
(defun c:SDDOCDATK () (sd:begin) (sd:tkx "DOC"))
(defun c:SDANHDATK () (sd:begin) (sd:tkx "ANH"))

(defun sd:nb-warn (f s) (setq *SD:NBWARN* (cons (strcat (car f) "=" s " (sai, dung mac dinh)") *SD:NBWARN*)))

;; Gia tri 1 truong tu chuoi trong bang (s nil / "" = mac dinh)
(defun sd:nb-val (f s / tp d r)
  (setq tp (nth 2 f) d (nth 3 f))
  (cond
    ((= tp 'note) nil)
    ((or (null s) (= s "")) (if (= tp 'bar) (sd:parse-bar d) d))
    ((member tp '(real real0))
     (cond ((distof (vl-string-translate "," "." s) 2)) (t (sd:nb-warn f s) d)))
    ((member tp '(int int0))
     (if (setq r (distof (vl-string-translate "," "." s) 2)) (fix (+ r (if (< r 0) -0.5 0.5))) (progn (sd:nb-warn f s) d)))
    ((= tp 'tog) (if (member (strcase s) '("1" "CO" "C" "X" "Y" "YES" "TRUE" "T")) t nil))
    ((= tp 'kw)
     (setq r (vl-some '(lambda (c) (if (or (= (strcase (sd:kv c)) (strcase s)) (= (strcase (sd:kl c)) (strcase s))) (sd:kv c)))
                      (nth 4 f)))
     (if r r (progn (sd:nb-warn f s) d)))
    ((= tp 'bar) (cond ((sd:parse-bar s)) (t (sd:nb-warn f s) (sd:parse-bar d))))
    ((= s "-") "")
    (t s)))

;; Danh sach truong + cap (KHOA . chuoi) cua 1 dong -> gia tri nhu hop thoai tra ve (*SD:FV*)
(defun sd:nb-fv (fields ov / r x)
  (foreach f fields
    (if (car f)
      (setq x (assoc (strcase (car f)) ov) ov (vl-remove x ov)
            r (cons (cons (car f) (sd:nb-val f (cdr x))) r))))
  (foreach x ov
    (if (and (car x) (/= (cdr x) "")) (setq *SD:NBWARN* (cons (strcat "cot " (car x) " khong co trong lenh nay (bo qua)") *SD:NBWARN*))))
  (reverse r))

;; Tach 1 dong CSV (co ngoac kep "a;b", "" = dau ngoac kep)
(defun sd:csv-split (s sep / i c q cur r)
  (setq i 1 cur "")
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (cond
      ((and q (= c "\"") (= (substr s (1+ i) 1) "\"")) (setq cur (strcat cur "\"") i (1+ i)))
      ((= c "\"") (setq q (not q)))
      ((and (not q) (= c sep)) (setq r (cons (vl-string-trim " \t" cur) r) cur ""))
      (t (setq cur (strcat cur c))))
    (setq i (1+ i)))
  (reverse (cons (vl-string-trim " \t" cur) r)))

;; Doc file bang -> ((so-dong LOAI ((KHOA . chuoi) ...)) ...). Dong "Loai;khoa1;khoa2..." = tieu de cho cac dong sau;
;; dong / o dau bat dau "#" = ghi chu; "sep=;" (Excel) chon dau phan cach, khong co thi tu nhan ; / tab / ,
(defun sd:nb-read (fn / f ln sep hdr cells rows n)
  (if (setq f (sd:open fn "r"))
    (progn
      (setq n 0)
      (while (setq ln (read-line f))
        (setq n (1+ n) ln (vl-string-trim " \t\r" ln))
        (if (and (= n 1) (>= (strlen ln) 3) (= (ascii ln) 239)) (setq ln (substr ln 4))) ; BOM UTF-8
        (cond
          ((= ln ""))
          ((wcmatch (strcase ln) "SEP=*") (setq sep (substr ln 5 1)))
          (t
           (if (null sep) (setq sep (cond ((vl-string-search ";" ln) ";") ((vl-string-search "\t" ln) "\t") (","))))
           (setq cells (sd:csv-split ln sep))
           (cond
             ((or (= (car cells) "") (= (substr (car cells) 1 1) "#")))
             ((= (strcase (car cells)) "LOAI") (setq hdr (mapcar 'strcase (cdr cells))))
             ((null hdr) (princ (strcat "\n[SD] Dong " (itoa n) ": chua co dong tieu de (Loai;name;...) phia tren, bo qua.")))
             (t (setq rows (cons (list n (strcase (car cells)) (vl-remove-if '(lambda (x) (= (car x) "")) (mapcar 'cons hdr (cdr cells))))
                                 rows)))))))
      (sd:close f)
      (reverse rows))))

;; Khung bao ((x0 y0) (x1 y1)) cua danh sach doi tuong
(defun sd:nb-bbox (ents / o a b mn mx x0 y0 x1 y1)
  (foreach e ents
    (setq o (vlax-ename->vla-object e))
    (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-GetBoundingBox (list o 'a 'b))))
      (setq mn (vlax-safearray->list a) mx (vlax-safearray->list b)
            x0 (if x0 (min x0 (car mn)) (car mn)) y0 (if y0 (min y0 (cadr mn)) (cadr mn))
            x1 (if x1 (max x1 (car mx)) (car mx)) y1 (if y1 (max y1 (cadr mx)) (cadr mx)))))
  (if x0 (list (list x0 y0) (list x1 y1))))

;;; --------------------------------------------------------------------------
;;;  SDDOCDA - Doc mat bang op lat da: dung lai cac o kin tu cac net roi (LINE / polyline mo hoac kin)
;;;  -> bang viec (CSV, cung dinh dang SDNHAPBANG: Loai;khoa...) de soat / bo sung o thieu -> ve polyline kin -> SDANHDA
;;;  Dung o kin = tach net tai giao diem va cho T, noi dau mut ho nho (dung sai), tim cac mat cua do thi phang.
;;; --------------------------------------------------------------------------
;; Bang bam (ky hieu): luu cac danh sach tam bang symbol, don bang sd:dm-clear
(setq *SD:DMKEYS* nil)
(defun sd:dm-hset (k v) (setq *SD:DMKEYS* (cons k *SD:DMKEYS*)) (set (read (strcat "SDDM_" k)) v))
(defun sd:dm-hget (k) (eval (read (strcat "SDDM_" k))))
(defun sd:dm-clear () (foreach k *SD:DMKEYS* (set (read (strcat "SDDM_" k)) nil)) (setq *SD:DMKEYS* nil))

;; Cac doan thang cua LINE / LWPOLYLINE (cung duoc chia nho nhu polyline): ((p q) ...)
(defun sd:dm-segs (ents / e ed ty pts cl a b r cv)
  (foreach e ents
    (setq ed (entget e) ty (cdr (assoc 0 ed)))
    (cond
      ((= ty "LINE") (setq r (cons (list (sd:2d (cdr (assoc 10 ed))) (sd:2d (cdr (assoc 11 ed)))) r)))
      ((= ty "LWPOLYLINE")
       (setq pts (sd:curve-pts e) cl (= 1 (logand 1 (cdr (assoc 70 ed)))))
       (if cl (setq pts (append pts (list (car pts)))))
       (setq a (car pts))
       (foreach b (cdr pts) (setq r (cons (list a b) r) a b)))
      ((member ty '("ARC" "CIRCLE" "SPLINE" "ELLIPSE"))
       (setq cv (sd:dm-curve e ty ed) pts (car cv) cl (cadr cv))
       (if cl (setq pts (append pts (list (car pts)))))
       (setq a (car pts))
       (foreach b (cdr pts) (setq r (cons (list a b) r) a b)))))
  (vl-remove-if '(lambda (s) (< (distance (car s) (cadr s)) 1e-6)) (reverse r)))

;; Hinh chieu diem p len doan a-b: (t . khoang-cach)
(defun sd:dm-proj (p a b / dx dy l2)
  (setq dx (- (car b) (car a)) dy (- (cadr b) (cadr a)) l2 (+ (* dx dx) (* dy dy)))
  (cons (/ (+ (* (- (car p) (car a)) dx) (* (- (cadr p) (cadr a)) dy)) l2)
        (/ (abs (- (* dx (- (cadr p) (cadr a))) (* dy (- (car p) (car a))))) (sqrt l2))))

;; Cac diem cat / cham cua moi doan: (so-doan x y uu-tien). Tu dong "snap" nhu OSNAP:
;;   uu-tien 3 = GIAO DIEM (that, hoac giao diem keo dai khi hai net ho / vuot nhau <= tol) -> dinh chinh xac
;;   uu-tien 2 = DAU MUT cua net
;;   uu-tien 1 = hinh chieu dau mut len doan khac (chi khi khong tinh duoc giao diem, vd 2 net gan song song)
(defun sd:dm-snap-add (pts a b q tol / p)
  ;; q = dau mut cua doan b nam gan doan a: lay giao diem (keo dai) cua 2 duong thang neu no cach q <= tol
  (if (and (setq p (inters (cadr a) (caddr a) (cadr b) (caddr b) nil))
           (<= (distance p q) tol))
    (cons (list (car a) (car p) (cadr p) 3) (cons (list (car b) (car p) (cadr p) 3) pts))
    (cons (list (car a) (car q) (cadr q) 1) pts)))

(defun sd:dm-points (recs tol / pts rest a b p q r qa qb)
  (foreach a recs
    (setq pts (cons (list (car a) (car (cadr a)) (cadr (cadr a)) 2) pts)
          pts (cons (list (car a) (car (caddr a)) (cadr (caddr a)) 2) pts)))
  (setq rest recs)
  (while rest
    (setq a (car rest) rest (cdr rest))
    (foreach b rest
      (if (and (<= (nth 3 b) (+ (nth 5 a) tol)) (>= (nth 5 b) (- (nth 3 a) tol))
               (<= (nth 4 b) (+ (nth 6 a) tol)) (>= (nth 6 b) (- (nth 4 a) tol)))
        (progn
          ;; giao diem that cua 2 doan
          (if (setq p (inters (cadr a) (caddr a) (cadr b) (caddr b) t))
            (setq pts (cons (list (car a) (car p) (cadr p) 3) (cons (list (car b) (car p) (cadr p) 3) pts))))
          ;; dau mut doan nay cham / gan giua doan kia (chu T): snap vao giao diem keo dai
          (foreach q (list (cadr b) (caddr b))
            (setq r (sd:dm-proj q (cadr a) (caddr a)))
            (if (and (> (car r) 0.0) (< (car r) 1.0) (<= (cdr r) tol))
              (setq pts (sd:dm-snap-add pts a b q tol))))
          (foreach q (list (cadr a) (caddr a))
            (setq r (sd:dm-proj q (cadr b) (caddr b)))
            (if (and (> (car r) 0.0) (< (car r) 1.0) (<= (cdr r) tol))
              (setq pts (sd:dm-snap-add pts b a q tol))))
          ;; 2 dau mut gan nhau nhung khong chua nhau (goc ho hoac vuot nhe): snap vao giao diem keo dai cua 2 duong
          (foreach qa (list (cadr a) (caddr a))
            (foreach qb (list (cadr b) (caddr b))
              (if (and (> (distance qa qb) 1e-6) (<= (distance qa qb) tol)
                       (setq p (inters (cadr a) (caddr a) (cadr b) (caddr b) nil))
                       (<= (distance p qa) tol) (<= (distance p qb) tol))
                (setq pts (cons (list (car a) (car p) (cadr p) 3) (cons (list (car b) (car p) (cadr p) 3) pts))))))))))
  pts)

;; Gop cac diem trong dung sai thanh nut (quet theo x): tra ve (so-nut (so-doan nut) ...) va luu toa do nut vao bang "P<nut>"
;; Toa do nut = giao diem (neu co) > dau mut > hinh chieu; nhieu diem cung uu-tien thi lay trung binh (khong lay diem dau tien theo x)
(defun sd:dm-cluster (pts tol / win nid x hit res k lst bp sx sy n)
  (setq nid 0)
  (foreach pt (sd:sort pts '(lambda (a b) (< (cadr a) (cadr b))))
    (setq x (cadr pt)
          win (vl-remove-if '(lambda (n) (< (cadr n) (- x tol))) win)
          hit (vl-some '(lambda (n) (if (<= (distance (cdr n) (cdr pt)) tol) (car n))) win))
    (if (null hit)
      (progn (setq hit nid nid (1+ nid)
                   win (cons (list hit (cadr pt) (caddr pt)) win))
             (sd:dm-hset (strcat "P" (itoa hit)) (list (cadr pt) (caddr pt)))
             (sd:dm-hset (strcat "M" (itoa hit)) nil)))
    ;; ghi nho cac diem thanh vien cua nut (set truc tiep, khong dang ky khoa lai)
    (set (read (strcat "SDDM_M" (itoa hit)))
         (cons (list (cadr pt) (caddr pt) (nth 3 pt)) (eval (read (strcat "SDDM_M" (itoa hit))))))
    (setq res (cons (list (car pt) hit) res)))
  ;; chot toa do tung nut theo thu tu uu-tien snap
  (setq k 0)
  (while (< k nid)
    (setq lst (eval (read (strcat "SDDM_M" (itoa k)))) bp 0 sx 0.0 sy 0.0 n 0)
    (foreach m lst (if (> (nth 2 m) bp) (setq bp (nth 2 m))))
    (foreach m lst
      (if (= (nth 2 m) bp) (setq sx (+ sx (car m)) sy (+ sy (cadr m)) n (1+ n))))
    (if (> n 0) (set (read (strcat "SDDM_P" (itoa k))) (list (/ sx n) (/ sy n))))
    (set (read (strcat "SDDM_M" (itoa k))) nil)
    (setq k (1+ k)))
  (cons nid res))

;; Canh (nut-nho . nut-lon), khong trung: noi cac nut lien tiep doc moi doan theo thu tu tham so
(defun sd:dm-edges (asg / rows sg pp pr r el out e)
  (foreach x asg
    (setq sg (sd:dm-hget (strcat "S" (itoa (car x)))) pp (sd:dm-hget (strcat "P" (itoa (cadr x)))))
    (setq rows (cons (list (car x) (car (sd:dm-proj pp (car sg) (cadr sg))) (cadr x)) rows)))
  (setq rows (sd:sort rows '(lambda (a b) (if (= (car a) (car b)) (< (cadr a) (cadr b)) (< (car a) (car b)))))
        pr (car rows))
  (foreach r (cdr rows)
    (if (and (= (car r) (car pr)) (/= (caddr r) (caddr pr)))
      (setq el (cons (if (< (caddr pr) (caddr r)) (cons (caddr pr) (caddr r)) (cons (caddr r) (caddr pr))) el)))
    (setq pr r))
  (setq el (sd:sort el '(lambda (a b) (if (= (car a) (car b)) (< (cdr a) (cdr b)) (< (car a) (car b))))) pr nil)
  (foreach e el
    (if (not (equal e pr)) (setq out (cons e out)))
    (setq pr e))
  out)

;; Danh sach ke "A<nut>" tu canh; bo nut cut (canh treo) lap di lap lai; sap ke theo goc nguoc chieu kim dong ho
(defun sd:dm-adj (edges n / e k v nd)
  (foreach e edges
    (foreach k (list (cons (car e) (cdr e)) (cons (cdr e) (car e)))
      (sd:dm-hset (strcat "A" (itoa (car k))) (cons (cdr k) (sd:dm-hget (strcat "A" (itoa (car k))))))))
  (setq nd 0 e nil)
  (while (< nd n)
    (if (<= (length (sd:dm-hget (strcat "A" (itoa nd)))) 1) (setq e (cons nd e)))
    (setq nd (1+ nd)))
  (while e
    (setq k (car e) e (cdr e))
    (foreach v (sd:dm-hget (strcat "A" (itoa k)))
      (sd:dm-hset (strcat "A" (itoa v)) (vl-remove k (sd:dm-hget (strcat "A" (itoa v)))))
      (if (= (length (sd:dm-hget (strcat "A" (itoa v)))) 1) (setq e (cons v e))))
    (sd:dm-hset (strcat "A" (itoa k)) nil))
  (setq nd 0)
  (while (< nd n)
    (setq k (strcat "A" (itoa nd)))
    (if (sd:dm-hget k)
      (sd:dm-hset k (mapcar 'cdr
                      (sd:sort (mapcar '(lambda (v) (cons (angle (sd:dm-hget (strcat "P" (itoa nd))) (sd:dm-hget (strcat "P" (itoa v)))) v))
                                       (sd:dm-hget k))
                               '(lambda (a b) (< (car a) (car b)))))))
    (setq nd (1+ nd))))

;; Cac mat (vong kin) cua do thi: danh sach vong nut, moi vong di nguoc chieu kim dong ho (mat trong) hoac cung chieu (vong ngoai)
(defun sd:dm-walk (n / res u v1 cyc cur nxt nb idx cnt nd)
  (setq nd 0)
  (while (< nd n)
    (setq u nd)
    (foreach v1 (sd:dm-hget (strcat "A" (itoa u)))
      (if (not (sd:dm-hget (strcat "V" (itoa u) "_" (itoa v1))))
        (progn
          (setq cyc nil cur u nxt v1 cnt 0)
          (while (and (not (sd:dm-hget (strcat "V" (itoa cur) "_" (itoa nxt)))) (< cnt 200000))
            (sd:dm-hset (strcat "V" (itoa cur) "_" (itoa nxt)) T)
            (setq cyc (cons cur cyc) cnt (1+ cnt)
                  nb (sd:dm-hget (strcat "A" (itoa nxt))) idx (vl-position cur nb)
                  cur nxt nxt (nth (rem (+ idx (length nb) -1) (length nb)) nb)))
          (setq res (cons (reverse cyc) res)))))
    (setq nd (1+ nd)))
  res)

(defun sd:dm-sarea (pts / s a b)
  (setq s 0.0 a (last pts))
  (foreach b pts (setq s (+ s (- (* (car a) (cadr b)) (* (car b) (cadr a)))) a b))
  (/ s 2.0))

;; Bo dinh thang hang (T giua canh, dinh thua): dinh lech <= 0.2 mm luon bo; dinh lech toi dung sai tol chi bo khi hai canh ke deu dai (T bi lech do noi ho),
;; de khong mat dinh cua cung nho
(defun sd:dm-simp (pts tol) (sd:dm-simp2 pts tol nil))

;; keeps = danh sach song song voi pts: T = dinh la nut giao (>= 3 canh) phai giu de cac polyline ke nhau trung dinh
(defun sd:dm-simp2 (pts tol keeps / n i a b c r dv)
  (setq n (length pts) i 0)
  (foreach b pts
    (setq a (nth (rem (+ i n -1) n) pts) c (nth (rem (1+ i) n) pts)
          dv (/ (abs (- (* (- (car c) (car a)) (- (cadr b) (cadr a))) (* (- (cadr c) (cadr a)) (- (car b) (car a)))))
                (max 1e-9 (distance a c))))
    (if (or (> dv tol) (nth i keeps)
            (and (> dv 0.2) (or (< (distance a b) 150.0) (< (distance b c) 150.0))))
      (setq r (cons b r)))
    (setq i (1+ i)))
  (reverse r))

;; Bo cac khung bao (khung phong, vien chua noi) la mat rat lon chua tu 3 o khac tro len; o co 1 - 2 cot ben trong van giu
(defun sd:dm-drop (polys / ars med big cnt res)
  (setq *SD:DMDROP* 0)
  (if (> (length polys) 3)
    (progn
      (setq ars (sd:sort (mapcar 'sd:dm-sarea polys) '<) med (nth (/ (length ars) 2) ars))
      (foreach p polys
        (setq big (> (sd:dm-sarea p) (* 2.5 med)) cnt 0)
        (if big
          (foreach q polys
            (if (and (< (sd:dm-sarea q) (sd:dm-sarea p)) (sd:inpoly (sd:centroid q) p)) (setq cnt (1+ cnt)))))
        (if (and big (>= cnt 3))
          (setq *SD:DMDROP* (1+ *SD:DMDROP*))
          (setq res (cons p res))))
      (reverse res))
    polys))

;; Cac mat trong (da giac, nguoc chieu kim dong ho, dien tich > amin mm2) tu cac doan thang: ((p1 p2 ...) ...)
(defun sd:dm-faces (segs tol amin / recs i s n pts cl asg edges polys cyc p)
  (sd:dm-clear)
  (setq i 0)
  (foreach s segs
    (sd:dm-hset (strcat "S" (itoa i)) s)
    (setq recs (cons (list i (car s) (cadr s) (min (car (car s)) (car (cadr s))) (min (cadr (car s)) (cadr (cadr s)))
                           (max (car (car s)) (car (cadr s))) (max (cadr (car s)) (cadr (cadr s))))
                     recs)
          i (1+ i)))
  (setq recs (reverse recs)
        pts (sd:dm-points recs tol)
        cl (sd:dm-cluster pts tol)
        n (car cl) asg (cdr cl)
        edges (sd:dm-edges asg))
  (sd:dm-adj edges n)
  (foreach cyc (sd:dm-walk n)
    (if (> (length cyc) 2)
      (progn
        (setq p (sd:dm-simp2 (mapcar '(lambda (k) (sd:dm-hget (strcat "P" (itoa k)))) cyc) tol
                             (mapcar '(lambda (k) (> (length (sd:dm-hget (strcat "A" (itoa k)))) 2)) cyc)))
        (if (and (> (length p) 2) (> (sd:dm-sarea p) amin))
          (setq polys (cons p polys))))))
  (sd:dm-clear)
  (sd:dm-drop (reverse polys)))

;; Hinh chu nhat? (4 dinh, moi goc vuong)
(defun sd:dm-rect-p (pts / i a b c ux uy vx vy ok)
  ;; dinh nut chu T nam tren canh (thang hang) khong lam o mat tinh chu nhat
  (if (> (length pts) 4) (setq pts (sd:dm-simp pts 0.3)))
  (if (= (length pts) 4)
    (progn
      (setq ok t i 0)
      (repeat 4
        (setq a (nth i pts) b (nth (rem (1+ i) 4) pts) c (nth (rem (+ i 2) 4) pts)
              ux (- (car a) (car b)) uy (- (cadr a) (cadr b)) vx (- (car c) (car b)) vy (- (cadr c) (cadr b)))
        (if (> (abs (/ (+ (* ux vx) (* uy vy)) (max 1e-9 (* (distance a b) (distance c b))))) 0.02) (setq ok nil))
        (setq i (1+ i)))
      ok)))

;; Cac o -> ban ghi (ma pts goc dai rong tam) theo thu tu lat ngoang nghoeo
(defun sd:dm-tiles (polys / tiles fr i)
  (foreach p polys
    (setq fr (sd:tile-frame p))
    (setq tiles (cons (list "" p (car fr) (cadr fr) (caddr fr) (cadddr fr)) tiles)))
  (setq i 0)
  (if tiles
    (mapcar '(lambda (r) (setq i (1+ i)) (cons (strcat "T" (itoa i)) (cddr r))) (sd:tile-order (reverse tiles)))))

;; Huong luoi chung cua cac o chu nhat (rad) neu >= 80% cung huong, nguoc lai nil -> SDANHDA tu xet tung vien
(defun sd:dm-frame (tiles / ks k best bn rects)
  (foreach r tiles
    (if (sd:dm-rect-p (cadr r))
      (progn (setq rects (1+ (cond (rects) (0))))
             (setq k (/ (fix (+ 0.5 (* 2.0 (rem (* 180.0 (/ (nth 2 r) pi)) (if (< (abs (- (nth 3 r) (nth 4 r))) 2.0) 90.0 180.0)))))
                        2.0))
             (if (assoc k ks) (setq ks (subst (cons k (1+ (cdr (assoc k ks)))) (assoc k ks) ks)) (setq ks (cons (cons k 1) ks))))))
  (foreach x ks (if (or (null best) (> (cdr x) bn)) (setq best (car x) bn (cdr x))))
  (if (and best (>= (* 1.0 bn) (* 0.8 rects))) (* pi (/ best 180.0))))

;; So -> chuoi (khong bi anh huong DIMZIN); chuoi -> so (nhan dau phay thap phan cua Excel)
(defun sd:dm-n (x p) (sd:rtos x p))
(defun sd:dm-num (s) (if (and s (/= s "")) (distof (vl-string-translate "," "." s) 2)))

;; ---------------- Cung / vong tron / spline -> da giac (chia nho), nhan lai cung khi ve ----------------
;; Diem doc theo cung / vong tron / spline / ellipse: (pts closed). Buoc 5 do (cung, tron), spline theo chieu dai
(defun sd:dm-curve (e ty ed / c r a0 a1 sw n i pts ln)
  (cond
    ((= ty "CIRCLE")
     (setq c (sd:2d (cdr (assoc 10 ed))) r (cdr (assoc 40 ed)) i 0)
     (repeat 72
       (setq pts (cons (polar c (* i (/ pi 36.0)) r) pts) i (1+ i)))
     (list (reverse pts) t))
    ((= ty "ARC")
     (setq c (sd:2d (cdr (assoc 10 ed))) r (cdr (assoc 40 ed)) a0 (cdr (assoc 50 ed)) a1 (cdr (assoc 51 ed))
           sw (- a1 a0))
     (if (<= sw 0.0) (setq sw (+ sw (* 2.0 pi))))
     (setq n (max 4 (fix (+ 1.0 (/ sw (/ pi 36.0))))) i 0)
     (repeat (1+ n)
       (setq pts (cons (polar c (+ a0 (* sw (/ i (float n)))) r) pts) i (1+ i)))
     (list (reverse pts) nil))
    (t
     (setq ln (vlax-curve-getDistAtParam e (vlax-curve-getEndParam e))
           n (max 12 (min 300 (+ 8 (fix (/ ln 25.0))))) i 0)
     (repeat (1+ n)
       (setq pts (cons (sd:2d (vlax-curve-getPointAtDist e (* ln (/ i (float n))))) pts) i (1+ i)))
     (list (reverse pts) (equal (vlax-curve-getPointAtParam e 0.0) (vlax-curve-getPointAtParam e (vlax-curve-getEndParam e)) 1e-6)))))

;; Goc re (rad, -pi..pi) tai dinh b khi di a -> b -> c
(defun sd:dm-turn (a b c / d)
  (setq d (- (angle b c) (angle a b)))
  (cond ((> d pi) (- d (* 2.0 pi))) ((< d (- pi)) (+ d (* 2.0 pi))) (t d)))

;; Do phinh cung (bulge) cua cung co goc ban kinh th (rad), chieu sg (+1 nguoc kim dong ho)
(defun sd:dm-bulge (th sg) (* sg (/ (sin (/ th 4.0)) (cos (/ th 4.0)))))

;; Nhan lai cung tu da giac: day dinh deu nhau, re deu cung chieu -> 1 cung. Tra ve ((x y bulge) ...)
(defun sd:dm-arcify (pts / n i ts ls fl tv a0 m k start runs run len j out al th sg)
  (setq n (length pts) i 0)
  (if (< n 6)
    (mapcar '(lambda (p) (list (car p) (cadr p) 0.0)) pts)
    (progn
      (foreach p pts
        (setq ts (cons (sd:dm-turn (nth (rem (+ i n -1) n) pts) p (nth (rem (1+ i) n) pts)) ts)
              ls (cons (distance p (nth (rem (1+ i) n) pts)) ls)
              i (1+ i)))
      (setq ts (reverse ts) ls (reverse ls) i 0)
      ;; dinh "trong cung": re 0.6 - 16 do, trung voi re dinh ke truoc hoac sau (+-12%), canh ke nhau xap xi
      (foreach tv ts
        (setq a0 (abs tv) m (nth (rem (+ i n -1) n) ts) k (nth (rem (1+ i) n) ts)
              fl (cons (if (and (> a0 0.0105) (< a0 0.28)
                                (or (and (> (* tv m) 0.0) (< (abs (- (abs m) a0)) (* 0.12 a0)))
                                    (and (> (* tv k) 0.0) (< (abs (- (abs k) a0)) (* 0.12 a0))))
                                (< (abs (- (nth (rem (+ i n -1) n) ls) (nth i ls))) (* 0.12 (nth i ls))))
                         t)
                       fl)
              i (1+ i)))
      (setq fl (reverse fl))
      (cond
        ((not (member nil fl))                      ; ca da giac la vong tron
         (if (= (rem n 2) 0)
           (progn
             (setq th (* (/ n 2) (/ (apply '+ (mapcar 'abs ts)) n)) sg (if (> (car ts) 0.0) 1.0 -1.0))
             (list (list (car (car pts)) (cadr (car pts)) (sd:dm-bulge th sg))
                   (list (car (nth (/ n 2) pts)) (cadr (nth (/ n 2) pts)) (sd:dm-bulge th sg))))
           (mapcar '(lambda (p) (list (car p) (cadr p) 0.0)) pts)))
        (t
         ;; dinh dau tien khong thuoc cung; bo cac day dinh cung ngan hon 2 dinh
         (setq start (vl-position nil fl)
               pts (append (sd:tail start pts) (sd:head start pts))
               ts (append (sd:tail start ts) (sd:head start ts))
               fl (append (sd:tail start fl) (sd:head start fl)) i 0)
         (while (< i n)
           (if (nth i fl)
             (progn (setq run 0 j i)
                    (while (and (< j n) (nth j fl)) (setq run (1+ run) j (1+ j)))
                    (if (< run 2) (setq fl (sd:dm-nilrun i run fl)))
                    (setq i j))
             (setq i (1+ i))))
         (setq i 0)
         (while (< i n)
           (setq len 0 j (1+ i))
           (while (and (< j n) (nth j fl)) (setq len (1+ len) j (1+ j)))
           (if (>= len 2)
             (progn
               (setq al (/ (apply '+ (mapcar 'abs (sd:head len (sd:tail (1+ i) ts)))) len)
                     th (* (1+ len) al) sg (if (> (nth (1+ i) ts) 0.0) 1.0 -1.0)
                     out (cons (list (car (nth i pts)) (cadr (nth i pts)) (sd:dm-bulge th sg)) out)
                     i (+ i len 1)))
             (setq out (cons (list (car (nth i pts)) (cadr (nth i pts)) 0.0) out)
                   i (1+ i))))
         (reverse out))))))

;; Thay k phan tu lien tiep bat dau tu i trong lst bang nil
(defun sd:dm-nilrun (i k lst / r j)
  (setq j 0)
  (foreach x lst
    (setq r (cons (if (and (>= j i) (< j (+ i k))) nil x) r) j (1+ j)))
  (reverse r))

;; ---------------- O co lo / cot ben trong: khoet, tach thanh cac vien lom (chu U / L) ----------------
;; Cat da giac loi theo nua mat phang x >= x0 (dir = 1) hoac x <= x0 (dir = -1); bo dinh trung
(defun sd:dm-clipx (poly x0 dir / out a b ina inb t0)
  (setq a (last poly) ina (>= (* dir (- (car a) x0)) -1e-9))
  (foreach b poly
    (setq inb (>= (* dir (- (car b) x0)) -1e-9))
    (cond
      ((and inb ina) (setq out (cons b out)))
      (inb (setq t0 (/ (- x0 (car a)) (- (car b) (car a)))
                 out (cons b (cons (list x0 (+ (cadr a) (* t0 (- (cadr b) (cadr a))))) out))))
      (ina (setq t0 (/ (- x0 (car a)) (- (car b) (car a)))
                 out (cons (list x0 (+ (cadr a) (* t0 (- (cadr b) (cadr a))))) out))))
    (setq a b ina inb))
  (setq out (reverse out) a nil)
  (vl-remove-if '(lambda (p) (if (and a (< (distance a p) 1e-6)) t (progn (setq a p) nil))) out))

(defun sd:dm-convex-p (pts / n i s c pos neg)
  (setq n (length pts) i 0)
  (repeat n
    (setq c (- (* (- (car (nth (rem (1+ i) n) pts)) (car (nth i pts))) (- (cadr (nth (rem (+ i 2) n) pts)) (cadr (nth (rem (1+ i) n) pts))))
               (* (- (cadr (nth (rem (1+ i) n) pts)) (cadr (nth i pts))) (- (car (nth (rem (+ i 2) n) pts)) (car (nth (rem (1+ i) n) pts))))))
    (if (> c 1e-6) (setq pos t))
    (if (< c -1e-6) (setq neg t))
    (setq i (1+ i)))
  (not (and pos neg)))

;; Vien lom: phan x >= cx (dir 1) hoac x <= cx (dir -1) cua outer, khoet phan lo hole cung phia (lo bi duong x = cx cat ngang)
(defun sd:dm-hole-piece (outer hole cx dir / p nh n k ch c1 c2 i j m pa pb p1 p2 out)
  (setq p (sd:dm-clipx outer cx dir) nh (sd:dm-clipx hole cx dir) n (length nh))
  (if (and (> (length p) 2) (> n 2))
    (progn
      ;; chuoi dinh cua lo khong nam tren duong cat, theo thu tu quanh lo: c1 -> ch -> c2
      (setq k 0)
      (while (and (< k n) (not (and (< (abs (- (car (nth k nh)) cx)) 1e-4)
                                    (>= (abs (- (car (nth (rem (1+ k) n) nh)) cx)) 1e-4))))
        (setq k (1+ k)))
      (if (< k n)
        (progn
          (setq c1 (nth k nh) j (rem (1+ k) n))
          (while (>= (abs (- (car (nth j nh)) cx)) 1e-4)
            (setq ch (cons (nth j nh) ch) j (rem (1+ j) n)))
          (setq ch (reverse ch) c2 (nth j nh) m (length p) i 0)
          ;; canh cua vien nam tren duong cat
          (while (and (< i m) (not (and (< (abs (- (car (nth i p)) cx)) 1e-4)
                                        (< (abs (- (car (nth (rem (1+ i) m) p)) cx)) 1e-4))))
            (setq i (1+ i)))
          (if (and ch (< i m))
            (progn
              (setq pa (nth i p) pb (nth (rem (1+ i) m) p))
              (if (<= (distance pa c1) (distance pa c2))
                (setq p1 c1 p2 c2)
                (setq p1 c2 p2 c1 ch (reverse ch)))
              (if (and (> (distance pa p1) 1e-3) (> (distance p2 pb) 1e-3))
                (progn
                  (setq j 0)
                  (foreach q p
                    (setq out (cons q out))
                    (if (= j i) (setq out (append (reverse (append (list p1) ch (list p2))) out)))
                    (setq j (1+ j)))
                  (reverse out))))))))))

;; Tach o outer (loi) co cac lo trong (holes, moi lo loi, khong chong nhau theo x) thanh cac vien lom, trong khung cuc bo; nil neu khong tach duoc
(defun sd:dm-split-hole (outer holes / hs n i h x0 x1 strip cx hb hc res bad)
  (setq hs (sd:sort holes '(lambda (a b) (< (apply 'min (mapcar 'car a)) (apply 'min (mapcar 'car b)))))
        n (length hs) i 0)
  (if (and (sd:dm-convex-p outer) (not (vl-some '(lambda (q) (not (sd:dm-convex-p q))) hs)))
    (progn
      (foreach h hs
        (setq x1 (if (< (1+ i) n) (/ (+ (apply 'max (mapcar 'car h)) (apply 'min (mapcar 'car (nth (1+ i) hs)))) 2.0))
              strip outer)
        (if (and x1 (>= (apply 'max (mapcar 'car h)) (apply 'min (mapcar 'car (nth (1+ i) hs))))) (setq bad t))
        (if x0 (setq strip (sd:dm-clipx strip x0 1)))
        (if x1 (setq strip (sd:dm-clipx strip x1 -1)))
        (setq cx (/ (+ (apply 'min (mapcar 'car h)) (apply 'max (mapcar 'car h))) 2.0)
              hb (sd:dm-hole-piece strip h cx -1) hc (sd:dm-hole-piece strip h cx 1))
        (if (and hb hc) (setq res (append res (list hb hc))) (setq bad t))
        (setq x0 x1 i (1+ i)))
      (if (not bad) res))))

;; Tim cac lo (o nam gon trong o khac, khong cham bien) va khoet: o chua lo thanh cac vien lom, o lo van giu (la o rieng hoac cot -> bo = 1)
;; Tra ve (cac-o so-lo so-vien so-o-khong-tach)
(defun sd:dm-holes (polys / recs i q r best isl nh np nf out hl fr c a lp pcs)
  (setq i 0)
  (foreach p polys
    (setq recs (cons (list i p (abs (sd:dm-sarea p)) (apply 'min (mapcar 'car p)) (apply 'min (mapcar 'cadr p))
                           (apply 'max (mapcar 'car p)) (apply 'max (mapcar 'cadr p)))
                     recs)
          i (1+ i)))
  (setq recs (reverse recs) nh 0 np 0 nf 0)
  (foreach q recs
    (setq best nil)
    (foreach r recs
      (if (and (/= (car r) (car q)) (> (nth 2 r) (nth 2 q))
               (<= (nth 3 r) (nth 3 q)) (<= (nth 4 r) (nth 4 q)) (>= (nth 5 r) (nth 5 q)) (>= (nth 6 r) (nth 6 q))
               (or (null best) (< (nth 2 r) (nth 2 best)))
               (not (vl-some '(lambda (v) (not (sd:inpoly v (cadr r)))) (cadr q))))
        (setq best r)))
    (if best (setq isl (cons (cons (car best) (car q)) isl))))
  (foreach r recs
    (setq hl (mapcar '(lambda (x) (cadr (nth (cdr x) recs))) (vl-remove-if-not '(lambda (x) (= (car x) (car r))) isl)))
    (if hl
      (progn
        (setq fr (sd:tile-frame (cadr r)) a (car fr) c (cadddr fr)
              pcs (sd:dm-split-hole (mapcar '(lambda (p) (sd:w2l c a p)) (cadr r))
                                    (mapcar '(lambda (h) (mapcar '(lambda (p) (sd:w2l c a p)) h)) hl)))
        (if pcs
          (progn
            (setq nh (+ nh (length hl)) np (+ np (length pcs)))
            (foreach q pcs
              (setq out (cons (sd:dm-simp (mapcar '(lambda (p) (sd:l2w c a p)) q) 0.3) out))))
          (setq nf (1+ nf) out (cons (cadr r) out))))
      (setq out (cons (cadr r) out))))
  (list (reverse out) nh np nf))

;; ---------------- JSON: xuat bang cho AI ngoai doc / dien, doc lai bang do AI dien ----------------
(defun sd:dm-json-write (fn tiles / f n pts)
  (if (setq f (sd:open fn "w"))
    (progn
      (write-line "{" f)
      (write-line "  \"dinh_dang\": \"SDDOCDA-1\"," f)
      (write-line "  \"don_vi\": \"mm\"," f)
      (write-line "  \"huong_dan\": [" f)
      (write-line "    \"Toa do tinh bang mm trong he toa do ban ve (goc 0,0; truc Y huong len). AI doc mat bang tu PDF / anh can quy ve toa do thuc dua vao mot kich thuoc da biet.\"," f)
      (write-line "    \"Moi vien la mot phan tu trong vien: hinh = CN (chu nhat, ve theo tam cx,cy + dai + rong + goc canh dai so voi truc X, do) hoac DAGIAC (da giac / hinh co cung: cac dinh trong pts dang x:y x:y ...; co the ghi pts la mang [[x,y],...]).\"," f)
      (write-line "    \"mavl = ma vat lieu (VD D1, G2); bo = 1 neu khong ve (cot, lo, o thua); ma = ma vien bat ky. Sau khi dien xong chay SDDOCDA, che do Ve, chon file nay.\"" f)
      (write-line "  ]," f)
      (write-line "  \"vien\": [" f)
      (setq n 0)
      (foreach r tiles
        (setq n (1+ n) pts (cadr r))
        (write-line
          (strcat "    {\"ma\": \"" (sd:jesc (car r)) "\", \"hinh\": \"" (if (sd:dm-rect-p pts) "CN" "DAGIAC") "\", \"dai\": " (sd:dm-n (nth 3 r) 1)
                  ", \"rong\": " (sd:dm-n (nth 4 r) 1)
                  ", \"goc\": " (sd:dm-n (rem (+ 360.0 (* 180.0 (/ (nth 2 r) pi))) (if (< (abs (- (nth 3 r) (nth 4 r))) 2.0) 90.0 180.0)) 2)
                  ", \"cx\": " (sd:dm-n (car (nth 5 r)) 1) ", \"cy\": " (sd:dm-n (cadr (nth 5 r)) 1)
                  ", \"pts\": \""
                  (if (sd:dm-rect-p pts) ""
                    (sd:join (mapcar '(lambda (q) (strcat (sd:dm-n (car q) 1) ":" (sd:dm-n (cadr q) 1))) pts) " "))
                  "\", \"mavl\": \"" (sd:jesc (cond ((nth 6 r)) (""))) "\", \"bo\": 0}"
                  (if (< n (length tiles)) "," ""))
          f))
      (write-line "  ]" f)
      (write-line "}" f)
      (sd:close f))))

;; Chuoi JSON bat dau tai ky tu i (la dau ngoac kep mo): tra ve (chuoi . vi-tri-sau-dau-dong)
(defun sd:dm-jstr (s i / r c n)
  (setq i (1+ i) r "" n (strlen s))
  (while (and (<= i n) (/= (setq c (substr s i 1)) "\""))
    (if (= c "\\")
      (progn (setq i (1+ i) c (substr s i 1))
             (setq r (strcat r (cond ((member c '("n" "t" "r")) " ") (t c)))))
      (setq r (strcat r c)))
    (setq i (1+ i)))
  (cons r (1+ i)))

(defun sd:dm-numch (c ext) (vl-string-search c (if ext "0123456789-.+eE" "0123456789-.")))

;; Mot doi tuong JSON phang (khoa: gia-tri, ...) -> ((KHOA . chuoi) ...); mang so -> dang x:y x:y; true -> 1; null / false -> trong
(defun sd:dm-jobj (s / i n c k v r tok nums dp)
  (setq i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\"")
       (setq v (sd:dm-jstr s i) k (car v) i (cdr v))
       (while (and (<= i n) (member (substr s i 1) '(" " ":" "\t"))) (setq i (1+ i)))
       (setq c (substr s i 1))
       (cond
         ((= c "\"")
          (setq v (sd:dm-jstr s i) r (cons (cons (strcase k) (car v)) r) i (cdr v)))
         ((= c "[")
          (setq nums nil dp 1 i (1+ i))
          (while (and (<= i n) (> dp 0))
            (setq c (substr s i 1))
            (cond
              ((= c "[") (setq dp (1+ dp) i (1+ i)))
              ((= c "]") (setq dp (1- dp) i (1+ i)))
              ((sd:dm-numch c nil)
               (setq tok "")
               (while (and (<= i n) (sd:dm-numch (substr s i 1) t))
                 (setq tok (strcat tok (substr s i 1)) i (1+ i)))
               (setq nums (cons tok nums)))
              (t (setq i (1+ i)))))
          (setq nums (reverse nums) tok "")
          (while (cdr nums)
            (setq tok (strcat tok (if (= tok "") "" " ") (car nums) ":" (cadr nums)) nums (cddr nums)))
          (setq r (cons (cons (strcase k) tok) r)))
         (t
          (setq tok "")
          (while (and (<= i n) (not (member (substr s i 1) '("," "}" " " "\t"))))
            (setq tok (strcat tok (substr s i 1)) i (1+ i)))
          (setq r (cons (cons (strcase k) (cond ((= tok "true") "1") ((member tok '("false" "null")) "") (t tok))) r)))))
      (t (setq i (1+ i)))))
  (reverse r))

;; Doc file JSON -> cac dong nhu sd:nb-read: ((so-thu-tu "VIENDA" ((KHOA . chuoi) ...)) ...)
(defun sd:dm-json-rows (fn / f ln txt i n c depth st tgt items inq esc k res)
  (if (setq f (sd:open fn "r"))
    (progn
      (setq txt "")
      (while (setq ln (read-line f)) (setq txt (strcat txt " " ln)))
      (sd:close f)
      (setq i 1 n (strlen txt) depth 0
            tgt (if (= (substr (vl-string-left-trim " \t" txt) 1 1) "[") 1 2))
      (while (<= i n)
        (setq c (substr txt i 1))
        (cond
          (inq (cond (esc (setq esc nil)) ((= c "\\") (setq esc t)) ((= c "\"") (setq inq nil))))
          ((= c "\"") (setq inq t))
          ((= c "{") (setq depth (1+ depth)) (if (= depth tgt) (setq st i)))
          ((= c "}")
           (if (and (= depth tgt) st)
             (setq items (cons (substr txt st (1+ (- i st))) items) st nil))
           (setq depth (1- depth))))
        (setq i (1+ i)))
      (setq k 0)
      (foreach obj (reverse items)
        (setq k (1+ k) res (cons (list k "VIENDA" (sd:dm-jobj obj)) res)))
      (reverse res))))

(defun sd:dm-json-p (fn / e) (and (setq e (vl-filename-extension fn)) (= (strcase e) ".JSON")))

;; Polyline kin tu da giac; nhan lai cung (bulge) neu co day dinh deu
(defun sd:dm-pl (pts lay / vs)
  (setq vs (sd:dm-arcify pts))
  (if (vl-some '(lambda (v) (/= (caddr v) 0.0)) vs)
    (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay) '(100 . "AcDbPolyline") (cons 90 (length vs)) '(70 . 1))
                     (apply 'append (mapcar '(lambda (v) (list (list 10 (car v) (cadr v)) (cons 42 (caddr v)))) vs))))
    (sd:pline pts t lay)))

;; Ma vat lieu cua tung o tu chu (TEXT / MTEXT) hoac hatch nam trong o: tra ve danh sach ma cung thu tu o (nil = khong co)
;; nguon "Chu" | "Hatch"; lochu = cac tien to chu cho phep, cach nhau dau phay (trong = moi chu)
(defun sd:dm-items (nguon lochu bb / ss i e ed r cd ty pre ok c)
  (if (and bb (setq ss (ssget "_W" (car bb) (cadr bb) (list (cons 0 (if (= nguon "Hatch") "HATCH" "TEXT,MTEXT"))))))
    (progn
      (setq i 0 pre (vl-remove "" (mapcar '(lambda (x) (strcase (vl-string-trim " " x))) (sd:split (cond (lochu) ("")) ","))))
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) ed (entget e) ty (cdr (assoc 0 ed)) cd nil)
        (cond
          ((= ty "HATCH")
           (setq cd (cond ((/= (strcase (cdr (assoc 2 ed))) "SOLID") (cdr (assoc 2 ed)))
                          ((assoc 62 ed) (strcat "M" (itoa (cdr (assoc 62 ed)))))
                          (t (cdr (assoc 8 ed))))))
          ((= ty "MTEXT") (setq cd (sd:mt-plain (strcat (apply 'strcat (mapcar 'cdr (vl-remove-if-not '(lambda (g) (= (car g) 3)) ed))) (cdr (assoc 1 ed))))))
          (t (setq cd (cdr (assoc 1 ed)))))
        (if cd (setq cd (vl-string-trim " \t" cd)))
        (if (and cd (/= cd "")
                 (or (null pre) (vl-some '(lambda (x) (wcmatch (strcase cd) (strcat x "*"))) pre)))
          (if (setq c (sd:nb-bbox (list e)))
            (setq r (cons (cons (list (/ (+ (car (car c)) (car (cadr c))) 2.0) (/ (+ (cadr (car c)) (cadr (cadr c))) 2.0)) cd) r))))))
    nil)
  r)

(defun sd:dm-codes (tiles nguon lochu / items bb pts mn mx code res)
  (if (and (member nguon '("Chu" "Hatch")) tiles)
    (progn
      (setq pts (apply 'append (mapcar 'cadr tiles))
            bb (list (list (- (apply 'min (mapcar 'car pts)) 1.0) (- (apply 'min (mapcar 'cadr pts)) 1.0))
                     (list (+ (apply 'max (mapcar 'car pts)) 1.0) (+ (apply 'max (mapcar 'cadr pts)) 1.0)))
            items (sd:dm-items nguon lochu bb))
      (foreach r tiles
        ;; nhieu chu trong 1 o: lay chu ngan nhat (ma vat lieu ngan, ghi chu thi dai)
        (setq code nil)
        (foreach it items
          (if (and (or (null code) (< (strlen (cdr it)) (strlen code))) (sd:inpoly (car it) (cadr r)))
            (setq code (cdr it))))
        (setq res (cons code res)))
      (reverse res))
    (mapcar '(lambda (r) nil) tiles)))

;; Gan them ma vao ban ghi o: (ma pts goc dai rong tam ma-vl)
(defun sd:dm-attach (tiles codes / i)
  (setq i -1)
  (mapcar '(lambda (r) (setq i (1+ i)) (append r (list (nth i codes)))) tiles))

;; Gan du lieu SD_TILE (ma VL, vien nguyen / cat, ma vien cat) cho cac polyline vua ve -> SDGACHTK / SDDATHO / SDGIACONG dung duoc
(defun sd:dm-tag (tiles els mat0 ten thk sc / i grp mat g fulls full pieces r n)
  (setq i 0)
  (foreach r tiles
    (setq mat (cond ((and (nth 6 r) (/= (nth 6 r) "")) (nth 6 r)) ((and mat0 (/= mat0 "")) mat0)))
    (if mat
      (if (setq g (assoc mat grp))
        (setq grp (subst (cons mat (cons (cons (nth i els) r) (cdr g))) g grp))
        (setq grp (cons (list mat (cons (nth i els) r)) grp))))
    (setq i (1+ i)))
  (setq n 0)
  (foreach g grp
    ;; kich thuoc vien nguyen = kich thuoc chu nhat hay gap nhat cua ma do
    (setq fulls nil)
    (foreach x (cdr g)
      (setq r (cdr x))
      (if (sd:dm-rect-p (cadr r))
        (setq full (list (fix (+ 0.5 (max (nth 3 r) (nth 4 r)))) (fix (+ 0.5 (min (nth 3 r) (nth 4 r)))))
              fulls (if (assoc full fulls) (subst (cons full (1+ (cdr (assoc full fulls)))) (assoc full fulls) fulls) (cons (cons full 1) fulls)))))
    (setq full nil)
    (foreach f fulls (if (or (null full) (> (cdr f) (cdr full))) (setq full f)))
    (setq full (if full (mapcar 'float (car full)) (list 0.0 0.0)) pieces nil)
    (foreach x (reverse (cdr g))
      (setq r (cdr x)
            pieces (cons (list (list (car x)) (nth 3 r) (nth 4 r) (abs (sd:dm-sarea (cadr r)))
                               (sd:rect-typ (nth 3 r) (nth 4 r) (abs (sd:dm-sarea (cadr r))) full)
                               (nth 5 r) (list 0.0 0.0) (list 0.0 0.0 0.0) (nth 2 r))
                         pieces)))
    (sd:code-pieces (reverse pieces) (car g) (cond ((and ten (/= ten "")) ten) ((car g))) (car full) (cadr full) thk nil sc)
    (setq n (+ n (length pieces))))
  n)

;; Ve cac o: (ma pts goc dai rong tam) -> polyline kin tren layer, tra ve danh sach ename
(defun sd:dm-draw (tiles dn sc / r els)
  (foreach r tiles
    (sd:dm-pl (cadr r) "SD-GACH-DOC")
    (setq els (cons (entlast) els))
    (if dn (sd:text (nth 5 r) (car r) (sd:tile-th (nth 3 r) (nth 4 r) sc) "MC" "SD-CHU")))
  (reverse els))

;; Ghi bang CSV (cung dinh dang SDNHAPBANG): moi o 1 dong VIENDA
(defun sd:dm-write (fn tiles / f r pts)
  (if (setq f (sd:open fn "w"))
    (progn
      (write-line "sep=;" f)
      (write-line "# BANG VIEN DA tu SDDOCDA - soat, sua, bo sung roi chay SDDOCDA > Ve (hoac SDANHDA tren cac polyline vua ve)" f)
      (write-line "# CN = chu nhat: ve theo tam (cx;cy) + dai + rong + goc; DAGIAC: ve theo cot pts (x:y x:y ...). Them o thieu = them dong CN co cx;cy;dai;rong;goc" f)
      (write-line "# bo = 1: khong ve dong do (cot, lo, o thua). Goc la goc canh dai so voi truc X (do)" f)
      (write-line "Loai;ma;hinh;dai;rong;goc;cx;cy;dtich;pts;mavl;bo;ghichu" f)
      (write-line "#;Ma vien;Hinh [CN/DAGIAC];Dai (mm);Rong (mm);Goc canh dai (do);Tam X;Tam Y;Dien tich (m2);Dinh DAGIAC (x:y x:y);Ma vat lieu (D1, G2...);Bo qua [1];Ghi chu" f)
      (foreach r tiles
        (setq pts (cadr r))
        (write-line
          (sd:join (list "VIENDA" (car r) (if (sd:dm-rect-p pts) "CN" "DAGIAC")
                         (sd:dm-n (nth 3 r) 1) (sd:dm-n (nth 4 r) 1)
                         (sd:dm-n (rem (+ 360.0 (* 180.0 (/ (nth 2 r) pi))) (if (< (abs (- (nth 3 r) (nth 4 r))) 2.0) 90.0 180.0)) 2)
                         (sd:dm-n (car (nth 5 r)) 1) (sd:dm-n (cadr (nth 5 r)) 1)
                         (sd:dm-n (/ (abs (sd:dm-sarea pts)) 1e6) 3)
                         (if (sd:dm-rect-p pts) ""
                           (sd:join (mapcar '(lambda (q) (strcat (sd:dm-n (car q) 1) ":" (sd:dm-n (cadr q) 1))) pts) " "))
                         (cond ((nth 6 r)) (""))
                         "" "")
                   ";")
          f))
      (sd:close f))))

;; Doc bang -> cac o (ma pts goc dai rong tam); canh bao dong loi
(defun sd:dm-read (fn / rows tiles v dai rong goc cx cy pts s q bad row hinh n)
  (setq n 0)
  (foreach row (if (sd:dm-json-p fn) (sd:dm-json-rows fn) (sd:nb-read fn))
    (if (= (cadr row) "VIENDA")
      (progn
        (setq v (caddr row))
        (if (member (cdr (assoc "BO" v)) '("1" "x" "X"))
          (setq n (1+ n))
          (progn
            (setq hinh (strcase (cond ((cdr (assoc "HINH" v))) ("CN")))
                  dai (sd:dm-num (cdr (assoc "DAI" v))) rong (sd:dm-num (cdr (assoc "RONG" v)))
                  goc (cond ((sd:dm-num (cdr (assoc "GOC" v)))) (0.0))
                  cx (sd:dm-num (cdr (assoc "CX" v))) cy (sd:dm-num (cdr (assoc "CY" v))) pts nil)
            (cond
              ((= hinh "DAGIAC")
               (foreach s (sd:split (cond ((cdr (assoc "PTS" v))) ("")) " ")
                 (if (and (/= s "") (setq q (sd:split s ":")) (cdr q) (sd:dm-num (car q)) (sd:dm-num (cadr q)))
                   (setq pts (cons (list (sd:dm-num (car q)) (sd:dm-num (cadr q))) pts))))
               (setq pts (reverse pts)))
              ((and dai rong cx cy (> dai 0.0) (> rong 0.0))
               (setq pts (mapcar '(lambda (p) (sd:l2w (list cx cy) (* pi (/ goc 180.0)) p))
                                 (list (list (/ dai -2.0) (/ rong -2.0)) (list (/ dai 2.0) (/ rong -2.0))
                                       (list (/ dai 2.0) (/ rong 2.0)) (list (/ dai -2.0) (/ rong 2.0)))))))
            (if (and pts (> (length pts) 2))
              (setq tiles (cons (list (cond ((cdr (assoc "MA" v))) ((strcat "T" (itoa (1+ (length tiles)))))) pts
                                      (* pi (/ goc 180.0)) (cond (dai) (0.0)) (cond (rong) (0.0)) (sd:centroid pts)
                                      (vl-string-trim " " (cond ((cdr (assoc "MAVL" v))) (""))))
                                tiles))
              (setq bad (cons (strcat "dong " (itoa (car row)) " (" (cond ((cdr (assoc "MA" v))) ("?")) "): thieu so lieu"
                                      (if (= hinh "DAGIAC") " pts (can >= 3 dinh x:y)" " (CN can cx;cy;dai;rong)"))
                              bad)))))))
    )
  (list (reverse tiles) (reverse bad) n))

(defun sd:dm-select (nguon lay / ss i ents)
  (cond
    ((= nguon "Layer") (setq ss (ssget "_X" (list '(0 . "LINE,LWPOLYLINE,ARC,CIRCLE,SPLINE,ELLIPSE") (cons 8 lay)))))
    (t (princ "\nQuet chon mat bang op lat (LINE, polyline, cung, tron, spline): ")
       (setq ss (ssget '((0 . "LINE,LWPOLYLINE,ARC,CIRCLE,SPLINE,ELLIPSE"))))))
  (if ss
    (progn (setq i 0)
           (repeat (sslength ss) (setq ents (cons (ssname ss i) ents) i (1+ i)))
           ;; bo net tren cac layer khong phai mat bang lat (mui bac, thang...)
           (if (and *SD:DMLAYX* (/= *SD:DMLAYX* ""))
             (progn
               (setq i (length ents)
                     ents (vl-remove-if '(lambda (e) (wcmatch (strcase (cdr (assoc 8 (entget e)))) (strcase *SD:DMLAYX*))) ents))
               (if (< (length ents) i) (princ (strcat "\n[SD] Bo qua " (itoa (- i (length ents))) " net tren layer " *SD:DMLAYX* ".")))))
           ents)))

;; Khoang cach tu diem toi doan a-b (co kep hai dau)
(defun sd:dm-segdist (p a b / tt)
  (setq tt (car (sd:dm-proj p a b)))
  (cond ((<= tt 0.0) (distance p a)) ((>= tt 1.0) (distance p b)) (t (cdr (sd:dm-proj p a b)))))

;; Dau mut khong noi voi net nao trong dung sai: ((x y khoang-cach) ...). khoang-cach <= 4 x dung sai = ho gan (gan nhu khep),
;; lon hon / khong co net gan = dau mut treo (khoang-cach = -1)
(defun sd:dm-near (segs tol / far i j q best res o mn)
  (setq far (* 4.0 tol) i 0)
  (foreach s segs
    (foreach q (list (car s) (cadr s))
      (setq best nil j 0)
      (foreach o segs
        (if (and (/= i j)
                 (>= (car q) (- (min (car (car o)) (car (cadr o))) far)) (<= (car q) (+ (max (car (car o)) (car (cadr o))) far))
                 (>= (cadr q) (- (min (cadr (car o)) (cadr (cadr o))) far)) (<= (cadr q) (+ (max (cadr (car o)) (cadr (cadr o))) far)))
          (progn (setq mn (sd:dm-segdist q (car o) (cadr o)))
                 (if (or (null best) (< mn best)) (setq best mn))))
        (setq j (1+ j)))
      (if (or (null best) (> best tol))
        (if (not (vl-some '(lambda (r) (< (distance r q) (* 2.0 far))) (mapcar 'list (mapcar 'car res) (mapcar 'cadr res))))
          (setq res (cons (list (car q) (cadr q) (if (and best (<= best far)) best -1.0)) res)))))
    (setq i (1+ i)))
  (reverse res))

;; Kiem tra o: ((x y ban-kinh chuoi) ...) - manh vun, nghi thieu net chia (o lon gap boi so o thuong), lech kich thuoc so voi o chuan
(defun sd:dm-odd (tiles sc / ars med keys modal r a w h rk out k kk mw mh cen)
  (foreach r tiles
    (if (sd:dm-rect-p (cadr r))
      (progn
        (setq ars (cons (* (nth 3 r) (nth 4 r)) ars)
              k (list (fix (+ 0.5 (max (nth 3 r) (nth 4 r)))) (fix (+ 0.5 (min (nth 3 r) (nth 4 r))))))
        (if (assoc k keys)
          (setq keys (subst (cons k (1+ (cdr (assoc k keys)))) (assoc k keys) keys))
          (setq keys (cons (cons k 1) keys))))))
  (if (> (length ars) 3)
    (progn
      (setq ars (sd:sort ars '<) med (nth (/ (length ars) 2) ars))
      (foreach kk keys (if (or (null modal) (> (cdr kk) (cdr modal))) (setq modal kk)))
      (setq mw (car (car modal)) mh (cadr (car modal)))
      (foreach r tiles
        (if (sd:dm-rect-p (cadr r))
          (progn
            (setq a (* (nth 3 r) (nth 4 r)) w (max (nth 3 r) (nth 4 r)) h (min (nth 3 r) (nth 4 r))
                  rk (min (* 0.25 h) (* 6.0 sc)) cen (nth 5 r))
            (cond
              ((< a (* 0.1 med))
               (setq out (cons (list (car cen) (cadr cen) rk (strcat (car r) ": manh vun " (sd:num w) "x" (sd:num h))) out)))
              ((> a (* 1.8 med))
               (setq out (cons (list (car cen) (cadr cen) rk
                                     (strcat (car r) ": nghi thieu net chia (~" (itoa (fix (+ 0.5 (/ a med)))) " o)"))
                               out)))
              ((and (>= (cdr modal) (* 0.4 (length ars)))
                    (< (abs (- w mw)) (* 0.15 mw)) (< (abs (- h mh)) (* 0.15 mh))
                    (> (+ (abs (- w mw)) (abs (- h mh))) 2.0))
               (setq out (cons (list (car cen) (cadr cen) rk
                                     (strcat (car r) ": lech kich thuoc " (sd:num w) "x" (sd:num h) " (chuan " (sd:num mw) "x" (sd:num mh) ")"))
                               out)))))))))
  (reverse out))

;; Bao cao kiem tra: in tom tat; khoanh do tren ban ve neu mark
(defun sd:dm-report (segs tiles tol mark sc / near odd nho ntreo)
  (if (> (length segs) 900)
    (princ "\n[SD] Nhieu net (>900): bo qua kiem tra ho / dau mut treo cho nhanh.")
    (progn
      (setq near (sd:dm-near segs tol))
      (foreach n near
        (if (>= (caddr n) 0.0) (setq nho (cons n nho)) (setq ntreo (cons n ntreo))))))
  (setq odd (sd:dm-odd tiles sc))
  (princ (strcat "\n[SD] Kiem tra: " (itoa (length nho)) " cho ho gan khep (dau mut cach net <= " (sd:num (* 4.0 tol)) " mm nhung > dung sai), "
                 (itoa (length ntreo)) " dau mut treo, " (itoa (length odd)) " o khac thuong."))
  (if (or nho ntreo odd)
    (if mark
      (progn
        (sd:make-layer "SD-KIEMTRA" 1 "Continuous" 35)
        (foreach n nho (sd:lk-mark (list (car n) (cadr n) 0.0) (* 2.0 sc) (strcat "ho " (sd:num (caddr n)) " mm: tang dung sai hoac noi net") sc))
        (foreach n ntreo (sd:lk-mark (list (car n) (cadr n) 0.0) (* 1.2 sc) "dau mut treo" sc))
        (foreach o odd (sd:lk-mark (list (car o) (cadr o) 0.0) (caddr o) (cadddr o) sc))
        (princ "\n[SD] Da khoanh do tren layer SD-KIEMTRA (xoa bang lenh SDKTLAT > hoac xoa layer)."))
      (progn
        (foreach o odd (princ (strcat "\n[SD]   " (cadddr o))))
        (if (or nho ntreo odd) (princ "\n[SD] Chay SDDOCDA che do Kiem de khoanh do tung cho tren ban ve.")))))
  (list (length nho) (length ntreo) (length odd)))

;; Cac da giac kin can NE khi dung o (mat cat mui bac, chi tiet): lay tu 1 layer hoac chon tren man hinh
(defun sd:dm-ne-get (/ ss i r)
  (cond
    ((= *SD:DMNEM* "Layer")
     (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *SD:DMNEL*) '(-4 . "&") '(70 . 1)))))
    ((= *SD:DMNEM* "Chon")
     (princ "\nChon cac polyline kin can ne (mat cat mui bac, chi tiet...): ")
     (setq ss (ssget '((0 . "LWPOLYLINE") (-4 . "&") (70 . 1))))))
  (if ss
    (progn (setq i 0)
           (repeat (sslength ss) (setq r (cons (sd:curve-pts (ssname ss i)) r) i (1+ i)))))
  r)

;; Diem nam trong da giac hoac sat canh (<= 2 mm)
(defun sd:dm-pt-in-or-on (pt poly / a on)
  (setq a (last poly))
  (foreach b poly (if (<= (sd:dm-segdist pt a b) 2.0) (setq on t)) (setq a b))
  (or on (sd:inpoly pt poly)))

;; O (da giac) nam trong vung ne: moi dinh nam trong / sat canh vung ne, hoac it nhat 1/2 so diem lay mau (tam + trung diem tam - dinh) nam trong
(defun sd:dm-in-ne (pts nes / cx cy smp)
  (setq cx (/ (apply '+ (mapcar 'car pts)) (float (length pts))) cy (/ (apply '+ (mapcar 'cadr pts)) (float (length pts)))
        smp (cons (list cx cy) (mapcar '(lambda (q) (list (/ (+ cx (car q)) 2.0) (/ (+ cy (cadr q)) 2.0))) pts)))
  (vl-some '(lambda (ne)
              (or (vl-every '(lambda (q) (sd:dm-pt-in-or-on q ne)) pts)
                  (>= (* 2 (length (vl-remove-if-not '(lambda (pt) (sd:inpoly pt ne)) smp))) (length smp))))
           nes))

(defun sd:dm-doc (nguon lay tol amin ve dn anh mng lochu mat0 ten thk khoet json / ents segs polys tiles fn sc nrect ntot els codes ncode hr jfn nes n0)
  (setq sc (sd:sc))
  (if (null (setq ents (sd:dm-select nguon lay)))
    (princ "\n[SD] Khong co net nao.")
    (progn
      (setq segs (sd:dm-segs ents))
      (princ (strcat "\n[SD] " (itoa (length segs)) " doan thang, dung sai " (sd:num tol) " mm..."))
      (if (> (length segs) 3000) (princ "\n[SD] Nhieu net (>3000): co the cham, doi chut."))
      (setq polys (sd:dm-faces segs tol (* 1e6 amin)))
      (if (null polys)
        (princ "\n[SD] Khong dung duoc o kin nao: thu tang dung sai noi dau mut, hoac giam dien tich toi thieu.")
        (progn
          (if khoet
            (progn
              (setq hr (sd:dm-holes polys) polys (car hr))
              (if (> (cadr hr) 0)
                (princ (strcat "\n[SD] Khoet " (itoa (cadr hr)) " lo / cot ben trong o: tach thanh " (itoa (caddr hr))
                               " vien lom (chu U / L). Lo / cot van la o rieng - dat bo = 1 trong bang neu la cot.")))
              (if (> (cadddr hr) 0)
                (princ (strcat "\n[SD] " (itoa (cadddr hr)) " o co lo khong tach duoc (lo khong loi / chong nhau theo huong cat): giu nguyen.")))))
          (setq tiles (sd:dm-tiles polys))
          ;; ne cac vung kin da chi dinh (mat cat mui bac...): khong ve / khong hatch / khong cat anh
          (if (and *SD:DMNEM* (/= *SD:DMNEM* "Khong") (setq nes (sd:dm-ne-get)))
            (progn
              (setq n0 (length tiles) tiles (vl-remove-if '(lambda (r) (sd:dm-in-ne (cadr r) nes)) tiles))
              (princ (strcat "\n[SD] Ne " (itoa (- n0 (length tiles))) " o nam trong " (itoa (length nes)) " vung kin (mat cat mui bac, chi tiet): khong ve, khong hatch."))))
          (setq ntot (length tiles) nrect 0)
          (foreach r tiles (if (sd:dm-rect-p (cadr r)) (setq nrect (1+ nrect))))
          (princ (strcat "\n[SD] Dung duoc " (itoa ntot) " o kin: " (itoa nrect) " chu nhat, " (itoa (- ntot nrect)) " hinh vat / da giac."))
          (if (> *SD:DMDROP* 0) (princ (strcat "\n[SD] Bo " (itoa *SD:DMDROP*) " khung bao ngoai (chua cac o khac ben trong).")))
          (setq codes (sd:dm-codes tiles mng lochu) ncode 0)
          (foreach c codes (if c (setq ncode (1+ ncode))))
          (if (/= mng "Khong")
            (princ (strcat "\n[SD] Ma vat lieu (" (if (= mng "Hatch") "hatch" "chu") "): " (itoa ncode) " / " (itoa ntot) " o co ma"
                           (if (< ncode ntot) " - o chua co ma de trong cot mavl trong bang." ""))))
          (setq tiles (sd:dm-attach tiles codes))
          (sd:dm-report segs tiles tol nil sc)
          (if (setq fn (sd:csv-name "_DocMatBang.csv"))
            (progn (sd:dm-write fn tiles)
                   (princ (strcat "\n[SD] Da ghi bang: " fn "  (mo Excel soat, them o thieu, bo = 1 cho cot / lo; roi SDDOCDA > Ve)"))))
          (if (and json (setq jfn (sd:csv-name "_DocMatBang.json")))
            (progn (sd:dm-json-write jfn tiles)
                   (princ (strcat "\n[SD] Da ghi JSON cho AI ngoai: " jfn "  (AI dien lai theo huong_dan trong file, roi SDDOCDA > Ve chon file .json)"))))
          (if (or ve anh)
            (progn
              (setq els (sd:dm-draw tiles dn sc))
              (princ (strcat "\n[SD] Da ve " (itoa (length els)) " polyline kin (layer SD-GACH-DOC)."))
              (sd:dm-tagmsg tiles els mat0 ten thk sc)
              (if anh (sd:dm-anhda tiles els)))
            (if dn (foreach r tiles (sd:text (nth 5 r) (car r) (sd:tile-th (nth 3 r) (nth 4 r) sc) "MC" "SD-CHU")))))))))

;; Gan SD_TILE neu co ma (trong bang / mac dinh) va bao ket qua
(defun sd:dm-tagmsg (tiles els mat0 ten thk sc / n)
  (if (or (and mat0 (/= mat0 "")) (vl-some '(lambda (r) (and (nth 6 r) (/= (nth 6 r) ""))) tiles))
    (progn (setq n (sd:dm-tag tiles els mat0 ten thk sc))
           (princ (strcat "\n[SD] Gan du lieu SD_TILE cho " (itoa n) " vien (ma VL, vien nguyen / cat): dung duoc SDGACHTK, SDDATHO, SDGIACONG.")))))

;; Che do Kiem: dung o + khoanh do cho ho / dau mut treo / o khac thuong
(defun sd:dm-kiem (nguon lay tol amin / ents segs polys tiles sc)
  (setq sc (sd:sc))
  (if (null (setq ents (sd:dm-select nguon lay)))
    (princ "\n[SD] Khong co net nao.")
    (progn
      (setq segs (sd:dm-segs ents) polys (sd:dm-faces segs tol (* 1e6 amin)) tiles (sd:dm-tiles polys))
      (princ (strcat "\n[SD] " (itoa (length segs)) " doan thang, " (itoa (length tiles)) " o kin."))
      (sd:dm-report segs tiles tol t sc))))

;; Chay SDANHDA ngay tren cac polyline vua ve, voi khung van chung cua luoi
(defun sd:dm-anhda (tiles els)
  (setq *SD:IFRAME* (sd:dm-frame tiles))
  (if *SD:IFRAME* (princ (strcat "\n[SD] Luoi chung huong " (sd:num (* 180.0 (/ *SD:IFRAME* pi))) " do: van da song song voi luoi.")))
  (sd:anhda els)
  (setq *SD:IFRAME* nil))

(defun sd:dm-ve (dn anh mat0 ten thk / fn res tiles els sc)
  (setq sc (sd:sc))
  (if (setq fn (getfiled "Chon file bang vien da (CSV hoac JSON tu SDDOCDA)" (getvar "DWGPREFIX") "csv;json" 0))
    (progn
      (setq res (sd:dm-read fn) tiles (car res))
      (foreach b (cadr res) (princ (strcat "\n[SD]   Loi " b)))
      (if (null tiles)
        (princ "\n[SD] Bang khong co dong VIENDA hop le.")
        (progn
          (setq els (sd:dm-draw tiles dn sc))
          (princ (strcat "\n[SD] Da ve " (itoa (length els)) " polyline kin tu bang (bo qua " (itoa (caddr res)) " dong bo = 1, "
                         (itoa (length (cadr res))) " dong loi)."))
          (sd:dm-tagmsg tiles els mat0 ten thk sc)
          (if anh (sd:dm-anhda tiles els)
            (princ "\n[SD] Tiep theo: SDANHDA (quet chon cac polyline vua ve), SDTKDA, SDGACHTK, SDVANDA.")))))))

;;; --------------------------------------------------------------------------
;;;  SDHANDINH - Han dinh: cac polyline sinh ra tu cung 1 diem giao cat phai co dinh TRUNG NHAU
;;;  1) cac dinh cach nhau <= dung sai duoc gop ve 1 toa do chung (trung binh)
;;;  2) dinh nam tren canh cua polyline ke ben (nut chu T) duoc chen them vao canh do
;;; --------------------------------------------------------------------------
;; Tach ban ghi polyline: (phan-dau (dinh ...) phan-duoi); dinh = ((x y) cap-phu ...) voi cap-phu = 40 / 41 / 42 / 91 ngay sau dinh
(defun sd:wd-split (ed / head vs cur tail in)
  (foreach p ed
    (cond
      (tail (setq tail (cons p tail)))
      ((= (car p) 10) (if cur (setq vs (cons (reverse cur) vs))) (setq cur (list (list (cadr p) (caddr p))) in t))
      ((and in (member (car p) '(40 41 42 91))) (setq cur (cons p cur)))
      (in (if cur (setq vs (cons (reverse cur) vs))) (setq cur nil tail (list p)))
      (t (setq head (cons p head)))))
  (if cur (setq vs (cons (reverse cur) vs)))
  (list (reverse head) (reverse vs) (reverse tail)))

(defun sd:wd-join (head vs tail)
  (append (mapcar '(lambda (p) (if (= (car p) 90) (cons 90 (length vs)) p)) head)
          (apply 'append (mapcar '(lambda (v) (cons (list 10 (car (car v)) (cadr (car v))) (cdr v))) vs))
          tail))

;; Gop diem trong dung sai thanh nut. Tra ve toa do nut (x y) theo dung thu tu diem dau vao
(defun sd:wd-cluster (pts tol / i items win hit asg nid x k res)
  (setq i 0)
  (foreach p pts (setq i (1+ i) items (cons (list i (car p) (cadr p)) items)))
  (setq nid 0)
  (foreach it (sd:sort items '(lambda (a b) (< (cadr a) (cadr b))))
    (setq x (cadr it)
          win (vl-remove-if '(lambda (n) (< (cadr n) (- x tol))) win)
          hit (vl-some '(lambda (n) (if (<= (distance (cdr n) (cdr it)) tol) (car n))) win))
    (if (null hit)
      (progn (setq hit nid nid (1+ nid) win (cons (list hit (cadr it) (caddr it)) win))
             (set (read (strcat "SDWD_S" (itoa hit))) (list 0.0 0.0 0))))
    (set (read (strcat "SDWD_S" (itoa hit)))
         (list (+ (cadr it) (car (eval (read (strcat "SDWD_S" (itoa hit))))))
               (+ (caddr it) (cadr (eval (read (strcat "SDWD_S" (itoa hit))))))
               (1+ (caddr (eval (read (strcat "SDWD_S" (itoa hit))))))))
    (setq asg (cons (cons (car it) hit) asg)))
  (setq k 0)
  (while (< k nid)
    (setq hit (eval (read (strcat "SDWD_S" (itoa k)))))
    (set (read (strcat "SDWD_P" (itoa k))) (list (/ (car hit) (caddr hit)) (/ (cadr hit) (caddr hit))))
    (set (read (strcat "SDWD_S" (itoa k))) nil)
    (setq k (1+ k)))
  (foreach a (sd:sort asg '(lambda (x y) (< (car x) (car y))))
    (setq res (cons (eval (read (strcat "SDWD_P" (itoa (cdr a))))) res)))
  (setq k 0)
  (while (< k nid) (set (read (strcat "SDWD_P" (itoa k))) nil) (setq k (1+ k)))
  (reverse res))

(defun sd:wd-cell (x y cs) (strcat "SDWD_G" (itoa (fix (sd:floor (/ x cs)))) "_" (itoa (fix (sd:floor (/ y cs))))))
(defun sd:floor (x) (if (and (< x 0.0) (/= x (fix x))) (1- (fix x)) (fix x)))

;; Cac nut nam trong thanh tren canh a-b (khong tinh a, b): ((t x y) ...) da sap theo t
(defun sd:wd-onedge (a b tol cs / x0 x1 y0 y1 ix iy r c pr)
  (setq x0 (- (min (car a) (car b)) tol) x1 (+ (max (car a) (car b)) tol)
        y0 (- (min (cadr a) (cadr b)) tol) y1 (+ (max (cadr a) (cadr b)) tol)
        ix (sd:floor (/ x0 cs)))
  (while (<= ix (sd:floor (/ x1 cs)))
    (setq iy (sd:floor (/ y0 cs)))
    (while (<= iy (sd:floor (/ y1 cs)))
      (foreach c (eval (read (strcat "SDWD_G" (itoa ix) "_" (itoa iy))))
        (if (and (> (distance c a) tol) (> (distance c b) tol))
          (progn (setq pr (sd:dm-proj c a b))
                 (if (and (> (car pr) 0.0) (< (car pr) 1.0) (<= (cdr pr) tol))
                     (setq r (cons (list (car pr) (car c) (cadr c)) r))))))
      (setq iy (1+ iy)))
    (setq ix (1+ ix)))
  (sd:sort r '(lambda (p q) (< (car p) (car q)))))

(defun c:SDHANDINH (/ ss i e ed sp recs allp cn k tol tdinh nodes keys cs cell nweld nins nfail nent new vs nv res dn nxt v2 ons a b c1 cnt)
  (sd:begin)
  (if (sd:dlg "Han dinh polyline (SDHANDINH)"
              (list (list "note" "Gop cac dinh sinh ra tu cung 1 diem giao cat ve 1 toa do, chen dinh nut chu T vao canh ke ben" 'note nil)
                    (list "tol" "Dung sai han dinh (mm)" 'real (sd:cfg "WD-TOL" 0.5))
                    (list "tdinh" "Chen dinh vao canh polyline ke ben (nut chu T)" 'tog t)))
    (progn
      (setq tol (sd:cfg-put "WD-TOL" (sd:v "tol")) tdinh (sd:v "tdinh") cs 500.0)
      (princ "\nQuet chon polyline can han dinh <Enter = tat ca polyline tren ban ve>: ")
      (if (not (setq ss (ssget '((0 . "LWPOLYLINE")))))
        (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (410 . "Model")))))
      (if (null ss)
        (princ "\n[SD] Khong co polyline.")
        (progn
          ;; doc tat ca polyline
          (setq i 0)
          (repeat (sslength ss)
            (setq e (ssname ss i) ed (entget e) sp (sd:wd-split ed) i (1+ i))
            (setq recs (cons (cons e sp) recs)))
          (setq recs (reverse recs) allp nil)
          (foreach r recs (foreach v (cadr (cdr r)) (setq allp (cons (car v) allp))))
          (setq allp (reverse allp) cn (sd:wd-cluster allp tol))
          ;; gan toa do nut moi cho tung dinh, dem so dinh bi doi
          (setq nweld 0 nodes nil)
          (setq new nil)
          (foreach r recs
            (setq vs nil)
            (foreach v (cadr (cdr r))
              (setq c1 (car cn) cn (cdr cn))
              (if (> (distance c1 (car v)) 1e-9) (setq nweld (1+ nweld)))
              (setq vs (cons (cons c1 (cdr v)) vs)))
            (setq new (cons (list (car r) (cadr r) (reverse vs) (cadddr r)) new)
                  nodes (append (mapcar 'car vs) nodes)))
          (setq new (reverse new))
          ;; luoi o de tra nut tren canh
          (setq keys nil nins 0)
          (if tdinh
            (progn
              (foreach c nodes
                (setq cell (sd:wd-cell (car c) (cadr c) cs))
                (if (not (member cell keys)) (setq keys (cons cell keys)))
                (set (read cell) (if (member c (eval (read cell))) (eval (read cell)) (cons c (eval (read cell))))))
              (setq new
                (mapcar
                  '(lambda (r / vs n k out a b ons own)
                     (setq vs (nth 2 r) n (length vs) k 0 out nil own (mapcar 'car vs))
                     (while (< k n)
                       (setq a (nth k vs) out (cons a out))
                       (if (or (< k (1- n)) (= 1 (logand 1 (cond ((cdr (assoc 70 (nth 1 r)))) (0)))))
                         (progn
                           (setq b (nth (rem (1+ k) n) vs))
                           (if (and (< (abs (cond ((cdr (assoc 42 (cdr a)))) (0.0))) 1e-9) (> (distance (car a) (car b)) 1e-9))
                             (foreach o (sd:wd-onedge (car a) (car b) tol cs)
                               (if (not (member (cdr o) own))
                                 (setq out (cons (list (cdr o)) out) nins (1+ nins)))))))
                       (setq k (1+ k)))
                     (list (car r) (nth 1 r) (reverse out) (nth 3 r)))
                  new))
              (foreach cell keys (set (read cell) nil))))
          ;; ghi lai
          (setq nent 0 nfail 0)
          (foreach r new
            (setq res (sd:wd-join (nth 1 r) (nth 2 r) (nth 3 r)))
            (if (not (equal res (entget (car r))))
              (if (vl-catch-all-error-p (vl-catch-all-apply 'entmod (list res)))
                (setq nfail (1+ nfail))
                (setq nent (1+ nent)))))
          (princ (strcat "\n[SD] SDHANDINH: " (itoa (length recs)) " polyline, da han " (itoa nweld) " dinh lech toa do, chen " (itoa nins)
                         " dinh nut T, sua " (itoa nent) " polyline" (if (> nfail 0) (strcat ", " (itoa nfail) " polyline khong sua duoc (layer khoa?)") "") "."))))))
  (sd:finish))

(defun c:SDDOCDA (/ che)
  (sd:begin)
  (if (sd:dlg "Doc mat bang op lat da (SDDOCDA)"
              (list (list "che" "Che do" 'kw (cond (*SD:DMCHE*) ("Doc"))
                          '(("Doc" . "Doc mat bang -> dung o kin -> ghi bang CSV de soat") ("Ve" . "Ve polyline kin tu bang CSV da soat")
                            ("Kiem" . "Kiem tra mat bang: khoanh do cho ho, dau mut treo, o khac thuong")))
                    (list "nguon" "Nguon net mat bang" 'kw (cond (*SD:DMNG*) ("Chon"))
                          '(("Chon" . "Quet chon tren ban ve") ("Layer" . "Tat ca net tren 1 layer"))
                          '("che" "Doc" "Kiem"))
                    (list "lay" "Ten layer chua net op lat" 'str (cond (*SD:DMLAY*) ("0")) nil '("nguon" "Layer"))
                    (list "layerx" "Bo qua cac layer (VD *STAIR*,*THANG*,*MUI*; cach nhau dau phay; trong = khong bo)" 'str (sd:cfg "LAYERX" "") nil '("che" "Doc" "Kiem"))
                    (list "ne" "Ne cac vung kin (mat cat mui bac, chi tiet): khong ve o, khong hatch" 'kw (cond (*SD:DMNEM*) ("Khong"))
                          '(("Khong" . "Khong ne") ("Layer" . "Ne cac polyline kin tren 1 layer") ("Chon" . "Chon cac polyline kin tren man hinh khi chay"))
                          '("che" "Doc"))
                    (list "layern" "Layer chua cac vung kin can ne" 'str (cond (*SD:DMNEL*) ("")) nil '("ne" "Layer"))
                    (list "tol" "Dung sai noi dau mut / ho (mm)" 'real (cond (*SD:DMTOL*) (5.0)) nil '("che" "Doc" "Kiem"))
                    (list "amin" "Bo o nho hon (m2)" 'real0 (cond (*SD:DMAMIN*) (0.01)) nil '("che" "Doc" "Kiem"))
                    (list "mng" "Lay ma vat lieu cua o tu" 'kw (cond (*SD:DMMNG*) ("Khong"))
                          '(("Khong" . "Khong lay (tu nhap cot mavl trong bang)") ("Chu" . "Chu (TEXT / MTEXT) nam trong o, vd D1, G2") ("Hatch" . "Hatch trong o (ten pattern / mau / layer)"))
                          '("che" "Doc"))
                    (list "lochu" "Chi nhan ma bat dau bang (vd D,G; trong = moi chu)" 'str (cond (*SD:DMLOC*) ("")) nil '("mng" "Chu"))
                    (list "lo" "Khoet lo / cot ben trong o (tach vien lom chu U / L)" 'tog t nil '("che" "Doc"))
                    (list "json" "Xuat them file JSON (cho AI ngoai doc / dien bang)" 'tog nil nil '("che" "Doc"))
                    (list "ve" "Ve luon polyline kin (bo qua buoc soat bang)" 'tog nil nil '("che" "Doc"))
                    (list "dn" "Danh so T1, T2... tren ban ve" 'tog t nil '("che" "Doc" "Ve"))
                    (list "mat0" "Ma VL mac dinh cho o chua co ma (trong = khong gan SD_TILE)" 'str (cond (*SD:DMMV0*) ("")) nil '("che" "Doc" "Ve"))
                    (list "ten" "Ten vat lieu (cho bang thong ke / gia cong)" 'str (cond (*SD:DMTEN*) ("")) nil '("che" "Doc" "Ve"))
                    (list "thk" "Chieu day da (mm)" 'real (cond (*SD:DMTHK*) (20.0)) nil '("che" "Doc" "Ve"))
                    (list "anh" "Chay SDANHDA ngay tren cac polyline (can ve luon / che do Ve)" 'tog nil nil '("che" "Doc" "Ve"))))
    (progn
      (setq che (sd:v "che") *SD:DMCHE* che *SD:DMLAYX* (sd:cfg-put "LAYERX" (cond ((sd:v "layerx")) ("")))
            *SD:DMNEM* (cond ((sd:v "ne")) ("Khong")) *SD:DMNEL* (cond ((sd:v "layern")) ("")))
      (cond
        ((= che "Ve")
         (setq *SD:DMMV0* (sd:v "mat0") *SD:DMTEN* (sd:v "ten") *SD:DMTHK* (sd:v "thk"))
         (sd:dm-ve (sd:v "dn") (sd:v "anh") (sd:v "mat0") (sd:v "ten") (sd:v "thk")))
        (t
         (setq *SD:DMNG* (sd:v "nguon") *SD:DMLAY* (sd:v "lay") *SD:DMTOL* (sd:v "tol") *SD:DMAMIN* (sd:v "amin"))
         (if (= che "Kiem")
           (sd:dm-kiem (sd:v "nguon") (sd:v "lay") (sd:v "tol") (sd:v "amin"))
           (progn
             (setq *SD:DMMNG* (sd:v "mng") *SD:DMLOC* (sd:v "lochu") *SD:DMMV0* (sd:v "mat0") *SD:DMTEN* (sd:v "ten") *SD:DMTHK* (sd:v "thk"))
             (sd:dm-doc (sd:v "nguon") (sd:v "lay") (sd:v "tol") (sd:v "amin") (sd:v "ve") (sd:v "dn") (sd:v "anh")
                        (sd:v "mng") (sd:v "lochu") (sd:v "mat0") (sd:v "ten") (sd:v "thk") (sd:v "lo") (sd:v "json"))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  DANH MUC LENH - nguon duy nhat cho SDHELP, SDPANEL, menu, toolbar, icon
;;;  (nhom  lenh  mo-ta  chu-tren-icon  lenh-tat)   [build.py doc danh sach nay de sinh menu]
;;; --------------------------------------------------------------------------
(setq *SD:CMDS*
  '(("Thiet lap va ban ve" "SDSET" "Thiet lap ty le, layer, text style, dimstyle" "SET" "TYLE")
    ("Op lat da granite / gach" "SDGACH" "Chia vien: thang/so le/xuong ca/chevron, vien, khe" "GACH" "CHV")
    ("Op lat da granite / gach" "SDCHANTUONG" "Len chan tuong + trien khai mat dung" "LEN" "LCT")
    ("Op lat da granite / gach" "SDRAITAM" "Rai panel / da lat theo kho: tam lon tu goc, tam di hinh mep bien, go bu, huong van" "RAI" "RTA")
    ("Op lat da granite / gach" "SDVANDA" "Hatch van da (file .pat) len vien: tiep noi / doi guong / xoay 4 chieu" "VAN" "VDA")
    ("Op lat da granite / gach" "SDQUYTRINH" "Hop thoai quy trinh da lat: goi y buoc tiep theo, chay tung buoc hoac lien hoan" "QT" "QTR")
    ("Op lat da granite / gach" "SDDOCDA" "Doc mat bang op lat: dung lai o kin tu net roi, ghi bang CSV de soat / bo sung, ve polyline kin, chay SDANHDA" "DOC" "DOD")
    ("Op lat da granite / gach" "SDMOANH" "Mo bien anh da: bien vien moi vuot anh nhung tam con du kho thi tu dich anh va cat lai" "MOB" "MOA")
    ("Op lat da granite / gach" "SDRON" "Doi ron giua cac vien: thu phong polyline vien, cap nhat hatch lien ket va cat lai anh, khong sua tay" "RON" "DRN")
    ("Op lat da granite / gach" "SDVAN" "Kiem tra van da lien tuc giua cac vien ke nhau (dua vao vi tri cat tren tam), khoanh moi noi dut van" "VKT" "LTV")
    ("Op lat da granite / gach" "SDKTLAT" "Kiem tra ban ve lat: vien cat hep / nho, ron khong deu, o thieu ma vat lieu" "KTL" "KLT")
    ("Op lat da granite / gach" "SDDIEMBD" "So sanh diem bat dau rai luoi vien: so vien cat, vien cat hep, hao hut; goi y diem tot nhat" "DBD" "DBT")
    ("Op lat da granite / gach" "SDKHEGIAN" "Khe co gian: khe sat tuong va khe phan vung vung lat, chong chiu dai toi da giua cac khe" "KGN" "KCG")
    ("Op lat da granite / gach" "SDTHOATNUOC" "Pheu thu nuoc + doc san: chenh cao den cac goc, khoanh vung vien cat quanh pheu" "TNG" "PTN")
    ("Op lat da granite / gach" "SDTUDONG" "Bat / tat tu dong: sua bien vien (grip, stretch...) thi anh IMAGECLIP tu cat lai theo bien moi" "TDG" "TDO")
    ("Op lat da granite / gach" "SDLOT" "Chay lo nhieu phong: rai vien cho tung khu vuc, diem bat dau tot nhat, thong ke tung vung + tong, tuy chon cat anh / hatch" "LOT" "NPH")
    ("Op lat da granite / gach" "SDRONIN" "Cho ron / duong vien hien ra khi in: doi mau trang + net, dua duong vien len tren anh" "RIN" "IRN")
    ("Op lat da granite / gach" "SDVATLIEU" "Danh sach vat lieu da dung (ma, kich thuoc, ron, khe): xem va xoa muc; SDGACH / SDLOT hien danh sach de chon lai nhanh" "VLD" "VLI")
    ("Op lat da granite / gach" "SDXOAVIEN" "Go bo vien trong vung chon: xoa polyline vien + anh + hatch + so hieu, lo ra chi tiet nam duoi (mat cat mui bac)" "XOV" "GOV")
    ("Op lat da granite / gach" "SDANHDA" "Cat anh tam da (imageclip) vao cac vien da quet chon: chieu van, xep it hao" "ANH" "ADA")
    ("Op lat da granite / gach" "SDTKDA" "Quet polyline vien da cat: bang thong ke theo nhom kich thuoc, chi tiet tung vien, CSV" "TKD" "TKD")
    ("Op lat da granite / gach" "SDDOCDATK" "Thong ke vien da sau SDDOCDA: bang nhom kich thuoc, dat tam da, CSV" "DTK" "DTK")
    ("Op lat da granite / gach" "SDANHDATK" "Thong ke tam da sau SDANHDA: so vien, hao hut tung tam, dat tam, CSV" "ATK" "ATK")
    ("Op lat da granite / gach" "SDGACHTK" "Thong ke vien + du tru dat hang" "TKV" "TKV")
    ("Op lat da granite / gach" "SDKHODA" "Kho da tho nhieu kich thuoc" "KHO" "KHO")
    ("Op lat da granite / gach" "SDDATHO" "Cat vien tu da tho: so do cat, hieu suat" "SLAB" "DTH")
    ("Op lat da granite / gach" "SDTHANGDA" "Cau thang da: mat bac, co bac, mui bac (thang / vat 45 / roi / CNC), khe LED, len, ra da kieu ABF" "THD" "TDA")
    ("Op lat da granite / gach" "SDGIACONG" "Ban ve gia cong tung ma vien" "GC" "GCV")
    ("Op lat da granite / gach" "SDLOP" "Chi tiet cau tao lop op / lat" "LOP" "CTL")
    ("Tien ich" "SDHANDINH" "Han dinh: gop dinh polyline lech nhau o cung diem giao cat, chen dinh nut chu T" "WLD" "HDI")
    ("Tien ich" "SDPANEL" "Bang lenh SDOpLat (hop thoai)" "ALL" "BLN")
    ("Tien ich" "SDHELP" "Danh sach lenh" "HLP" "HDL")
    ("Op lat da granite / gach" "SDBLOCKDA" "Block chi tiet da: tao block mat cat mui bac tu mau, quet hinh tao block, chen file .dwg, luu ra .dwg, mo Block Editor them thong so dong" "BCD" "KCD")
    ("Op lat da granite / gach" "SDTRINH" "Ban trinh khach: bang chu thich vat lieu co o mau anh da (A1 1:50) va che do trinh khach lam mo nen kien truc, an layer nhan" "TRK" "BTK")
    ("Op lat da granite / gach" "SDKHUNGIN" "Khung in A1 / A3 tu dung: khung ten, huong Bac, thuoc ty le, dat san cai dat in cho SDIN / SDTAOLAYOUT" "KHI" "KIN")
    ("Op lat da granite / gach" "SDKHAOSAT" "Dung phong tu file so do khao sat (room,ab,bc,cd,da,ac,bd): 4 canh + cheo, xep hang tin cay A / B / C / X / D, ve polyline phong lam bien cho SDGACH / SDLOT" "KSA" "KSH")
    ("Op lat da granite / gach" "SDCHIABAC" "Chia bac thang tu cao do (so voi +-0.000): chieu cao bac, lam tron don phan lech, bang cao do hoan thien / ket cau tung bac va chieu nghi, dat san SDTHANGDA" "CBA" "CHB")
    ("Op lat da granite / gach" "SDMAVIEN" "Ma vien theo hinh dang: cung vat lieu va hinh dang cung ma (VD G1-01), nho trong ban ve, ghi len vien, bang + CSV" "MVI" "SMV")
    ("Op lat da granite / gach" "SDKIEMTONG" "Luot kiem tong: ho so so lieu, vien hep / nho, ron khong deu, luoi ron lech, chuoi cao do; bao cao + CSV" "KTG" "KTO")
    ("Op lat da granite / gach" "SDHOSO" "Ho so so lieu du an: ron, cao do, doc, du...; danh dau da xac nhan / chua xac nhan, canh bao khi lenh dung so chua xac nhan, bang ra ban ve" "HSO" "SLD")
    ("Op lat da granite / gach" "SDDIMVIEN" "Dim tu dong theo hang vien: chuoi tung vien + tong, ngang / dung, ngoai phong hoac trong phong" "DMV" "DVI")
    ("Op lat da granite / gach" "SDOPTUONG" "Op tuong trung ron san: mat dung trai phang, ron dung theo ron san, kiem tra trung ron" "OTU" "OPTU")
    ("Op lat da granite / gach" "SDTRUNGRON" "Kiem tra luoi ron lien tuc xuyen cac phong: nhom vien lech luoi chinh, khoanh may, goi y dich" "TRG" "RLE")
    ("Op lat da granite / gach" "SDBACCAODO" "Cho doi cao do (nguong WC, mep ho, chan thanh): gan du mm, SDCATDU tu nhan" "BCO" "CDB")
    ("Op lat da granite / gach" "SDLIENCAODO" "Chuoi cao do: san chinh, san WC (ha cot, doc ve pheu thu), san ho, muc nuoc, day ho; chenh cao tung muc, canh bao, so do" "LCD" "LKD")
    ("Op lat da granite / gach" "SDHOBOI" "Ho boi: doc day dau nong - dau sau, duong dong muc day, khe co gian, mat cat doc + bang cao do day theo vien, doi chieu TCVN 4260:2012 / ISPSC 2015" "HBO" "HOB")
    ("Op lat da granite / gach" "SDMAP" "Thu vien map (anh) da granite co san: chen anh tam da dung kich thuoc that de SDANHDA cat vao vien; tha them .jpg / .png vao thu muc Maps" "MAP" "TVM")
    ("Op lat da granite / gach" "SDDICHVAN" "Dich van da tung buoc: nhich anh tam da duoi bien vien (trai / phai / len / xuong, buoc mm), bien dung yen, co hoan buoc" "DVA" "DCV")
    ("Op lat da granite / gach" "SDCATDU" "Cat du sat tuong: vien cat nao, canh nao phai cat dai ra (+du mm) de be lai khi thi cong; gach do tren ban ve, bang kich thuoc cat, CSV" "CDU" "CTD")
    ("Op lat da granite / gach" "SDDUTOAN" "Du toan tien da theo don gia m2 tung ma vat lieu (nho lai), hao hut, cong lat, VAT; bang + CSV" "DTO" "DTD")
    ("Op lat da granite / gach" "SDPHUONGAN" "Phuong an lat A / B tren mot to: nhan + bang ngan (so vien, nguyen / cat, hao hut) + khung in bao ca hai" "PAB" "PHA")
    ("Tien ich" "SDTUNAP" "Bat / tat tu nap SDOpLat moi khi mo AutoCAD (khong can APPLOAD lai)" "TNP" "AUL")
    ("Tien ich" "SDMENU" "Cai menu + toolbar + Ribbon" "MNU" "CMN")
    ("Tien ich" "SDDLG" "Bat / tat hop thoai nhap lieu" "DLG" "HTN")))


;; Lenh tat: moi muc trong danh muc sinh 1 lenh ngan goi lenh chinh (vd TKT -> SDTKTHEP)
(foreach c *SD:CMDS*
  (if (nth 4 c)
    (eval (list 'defun (read (strcat "c:" (nth 4 c))) '()
                (list (read (strcat "c:" (cadr c))))))))

(defun sd:groups (/ r)
  (foreach c *SD:CMDS* (if (not (member (car c) r)) (setq r (cons (car c) r))))
  (reverse r))

;;; --------------------------------------------------------------------------
;;;  SDHELP - Danh sach lenh
;;; --------------------------------------------------------------------------
(defun sd:pad (s n) (strcat s (substr "                    " 1 (max 1 (- n (strlen s))))))

(defun c:SDHELP (/ g)
  (textscr)
  (princ (strcat "\n================ SDOPLAT TOOLS v" *SD:VER* " ================"
                 "\n Ty le: 1/" (itoa *SD:SCALE*) "   chi tiet: 1/" (itoa *SD:DETSCALE*)))
  (foreach c *SD:CMDS*
    (if (/= (car c) g) (progn (setq g (car c)) (princ (strcat "\n -- " g " --"))))
    (princ (strcat "\n  " (sd:pad (cadr c) 14) (sd:pad (nth 4 c) 6) (caddr c))))
  (princ "\n Cot 2 la lenh tat. Go SDPANEL (BLN) de mo bang lenh; xem them dist/HuongDanLenh.html.")
  (princ "\n================================================================")
  (princ))

;;; --------------------------------------------------------------------------
;;;  SDPANEL - Bang lenh dang hop thoai (DCL tao tu dong, chay ca ZWCAD/BricsCAD)
;;; --------------------------------------------------------------------------
(defun sd:panel-fill (g)
  (setq *SD:PCMDS* (vl-remove-if-not '(lambda (c) (= (car c) g)) *SD:CMDS*) *SD:PIDX* 0)
  (start_list "lst")
  (mapcar '(lambda (c) (add_list (strcat (sd:pad (cadr c) 14) (sd:pad (nth 4 c) 6) (caddr c)))) *SD:PCMDS*)
  (end_list)
  (set_tile "lst" "0"))

(defun c:SDPANEL (/ fn f id res cmd)
  (setq fn (vl-filename-mktemp "sdpanel" nil ".dcl"))
  (if (setq f (open fn "w"))
    (progn
      (foreach l '("sdpanel : dialog { label = \"SDOpLat Tools\";"
                   "  : popup_list { key = \"grp\"; label = \"Nhom lenh:\"; width = 46; }"
                   "  : list_box { key = \"lst\"; height = 16; width = 72; }"
                   "  : text { label = \"Nhap dup hoac OK de chay lenh.\"; }"
                   "  ok_cancel;"
                   "}")
        (write-line l f))
      (close f)))
  (if (and (setq id (load_dialog fn)) (> id 0) (new_dialog "sdpanel" id))
    (progn
      (start_list "grp") (mapcar 'add_list (sd:groups)) (end_list)
      (sd:panel-fill (car (sd:groups)))
      (action_tile "grp" "(sd:panel-fill (nth (atoi $value) (sd:groups)))")
      (action_tile "lst" "(setq *SD:PIDX* (atoi $value)) (if (= $reason 4) (done_dialog 1))")
      (action_tile "accept" "(setq *SD:PIDX* (atoi (get_tile \"lst\"))) (done_dialog 1)")
      (setq res (start_dialog))
      (unload_dialog id)
      (vl-file-delete fn)
      (if (and (= res 1) (setq cmd (cadr (nth *SD:PIDX* *SD:PCMDS*))))
        (vla-SendCommand (sd:doc) (strcat cmd "\n"))))
    (princ "\n[SD] Khong mo duoc hop thoai."))
  (princ))

;;; --------------------------------------------------------------------------
;;;  SDTRINH - Ban trinh khach: (Chuthich) bang chu thich vat lieu co o mau anh da, ma, ten, kich thuoc, so luong, dien tich;
;;;  (Bat / Tat) che do trinh khach: lam mo nen kien truc (mau xam nhat, net manh 0,09), an cac layer nhan ky thuat, Tat tra lai nhu cu.
;;;  Kich thuoc bang tinh theo kho giay: 1 mm tren giay = tl don vi ban ve (A1 ty le 1:50 -> tl = 50).
;;; --------------------------------------------------------------------------
;; Gom cac vien theo ma vat lieu: ((ma ten w h day so-luong dien-tich-m2 anh) ...)
(defun sd:tr-collect (/ ss i e xd g rows ims)
  (setq ims (ssget "_X" '((0 . "IMAGE") (-3 ("SD_ANH")))))
  (if (setq ss (ssget "_X" '((0 . "LWPOLYLINE") (-3 ("SD_TILE")))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))))
        (if (and (>= (length xd) 12) (/= (nth 1 xd) "X"))
          (progn
            (if (setq g (assoc (nth 0 xd) rows))
              (setq rows (subst (list (nth 0 g) (nth 1 g) (nth 2 g) (nth 3 g) (nth 4 g) (1+ (nth 5 g)) (+ (nth 6 g) (nth 5 xd))
                                      (cond ((nth 7 g)) ((if ims (sd:im-find (sd:curve-pts e) ims)))))
                                g rows))
              (setq rows (cons (list (nth 0 xd) (nth 7 xd) (nth 8 xd) (nth 9 xd) (nth 11 xd) 1 (nth 5 xd)
                                     (if ims (sd:im-find (sd:curve-pts e) ims)))
                               rows))))))))
  (sd:sort rows '(lambda (a b) (< (car a) (car b)))))

;; O mau: ban sao anh tam da, bo clip, xoay thang truc, phong vua phu o sw x sh roi cat; ban sao khong mang SD_ANH (khong lam roi cac lenh ghep anh)
(defun sd:tr-swatch (im x0 y0 sw sh lay / o cp ce g a s p)
  (setq o (vlax-ename->vla-object im) cp (vla-Copy o) ce (vlax-vla-object->ename cp))
  (vl-catch-all-apply 'entmod (list (append (entget ce) (list (list -3 (list "SD_ANH"))))))
  (command "_.IMAGECLIP" ce "_D")
  (setq g (sd:im-geom ce) a (cadr g) p (car g))
  (vla-Rotate cp (vlax-3d-point (list (car p) (cadr p) 0.0)) (- a))
  (setq s (max (/ sw (caddr g)) (/ sh (cadddr g))))
  (vla-ScaleEntity cp (vlax-3d-point (list (car p) (cadr p) 0.0)) s)
  (vla-Move cp (vlax-3d-point (list (car p) (cadr p) 0.0)) (vlax-3d-point (list x0 y0 0.0)))
  (vla-put-Layer cp lay)
  (command "_.IMAGECLIP" ce "_N" "_P" (list x0 y0) (list (+ x0 sw) y0) (list (+ x0 sw) (+ y0 sh)) (list x0 (+ y0 sh)) ""))

;; Ve bang chu thich, goc tren trai o, tl = don vi ban ve tren 1 mm giay
(defun sd:tr-legend (rows o tl / lay cy hh rh x y n r xs hdr tot k a)
  (setq lay (sd:make-layer "SD-CHUTHICH" 7 "Continuous" 18)
        xs (list 0.0 26.0 44.0 116.0 148.0 164.0 184.0 210.0)
        hdr (list "M\\U+1EABu" "M\\U+00E3" "T\\U+00EAn v\\U+1EADt li\\U+1EC7u" "K\\U+00EDch th\\U+01B0\\U+1EDBc (mm)" "D\\U+00E0y" "SL" "Di\\U+1EC7n t\\U+00EDch (m\\U+00B2)")
        hh 8.0 rh 16.0 x (car o) y (cadr o))
  (sd:text (list x (+ y (* 3.0 tl))) "B\\U+1EA2NG CH\\U+00DA TH\\U+00CDCH V\\U+1EACT LI\\U+1EC6U" (* 5.0 tl) "L" lay)
  (setq tot (+ hh (* rh (length rows))))
  (sd:pline (list (list x y) (list (+ x (* tl 210.0)) y) (list (+ x (* tl 210.0)) (- y (* tl tot))) (list x (- y (* tl tot)))) t lay)
  (setq k 0)
  (foreach c hdr
    (sd:text (list (+ x (* tl (+ (nth k xs) 1.5))) (- y (* tl (/ hh 2.0)))) c (* 3.0 tl) "ML" lay) (setq k (1+ k)))
  (sd:line (list x (- y (* tl hh))) (list (+ x (* tl 210.0)) (- y (* tl hh))) lay)
  (foreach xc (cdr (reverse (cdr (reverse xs))))
    (sd:line (list (+ x (* tl xc)) y) (list (+ x (* tl xc)) (- y (* tl tot))) lay))
  (setq n 0 a 0.0)
  (foreach r rows
    (setq cy (- y (* tl (+ hh (* rh n)))) n (1+ n))
    (sd:line (list x (- cy (* tl rh))) (list (+ x (* tl 210.0)) (- cy (* tl rh))) lay)
    ;; o mau
    (if (and (nth 7 r) (vl-catch-all-error-p
                          (vl-catch-all-apply 'sd:tr-swatch (list (nth 7 r) (+ x (* tl 2.0)) (- cy (* tl (+ rh -1.0))) (* tl 22.0) (* tl 14.0) lay))))
      (sd:text (list (+ x (* tl 3.0)) (- cy (* tl (/ rh 2.0)))) "(l\\U+1ED7i \\U+1EA3nh)" (* 2.5 tl) "ML" lay))
    (if (null (nth 7 r))
      (sd:text (list (+ x (* tl 3.0)) (- cy (* tl (/ rh 2.0)))) "(kh\\U+00F4ng \\U+1EA3nh)" (* 2.5 tl) "ML" lay)
      (sd:pline (list (list (+ x (* tl 2.0)) (- cy (* tl (+ rh -1.0)))) (list (+ x (* tl 24.0)) (- cy (* tl (+ rh -1.0))))
                      (list (+ x (* tl 24.0)) (- cy (* tl 1.0))) (list (+ x (* tl 2.0)) (- cy (* tl 1.0)))) t lay))
    (setq k 1)
    (foreach v (list (nth 0 r) (nth 1 r) (strcat (sd:num (nth 2 r)) " x " (sd:num (nth 3 r))) (sd:num (nth 4 r)) (itoa (nth 5 r)) (sd:rtos (nth 6 r) 2))
      (sd:text (list (+ x (* tl (+ (nth k xs) 1.5))) (- cy (* tl (/ rh 2.0)))) v (* 3.0 tl) "ML" lay) (setq k (1+ k)))
    (setq a (+ a (nth 6 r))))
  (sd:text (list (+ x (* tl 186.0)) (- y (* tl (+ tot 5.0)))) (strcat "T\\U+1ED5ng: " (sd:rtos a 2) " m\\U+00B2") (* 3.5 tl) "L" lay)
  (length rows))

;; Che do trinh khach: lam mo nen, an layer nhan; nho mau / net / bat-tat cu de Tat tra lai
(defun sd:tr-on (hide fade / lays old nm l hs)
  (if (vlax-ldata-get "SD" "TRINH-OLD")
    (princ "\n[SD] Che do trinh khach dang bat (g\\U+00F5 Tat de tra lai).")
    (progn
      (setq lays (vla-get-Layers (sd:doc)) hs (mapcar 'strcase (sd:split hide ",")))
      (vlax-for l lays
        (setq nm (vla-get-Name l))
        (if (and (not (wcmatch (strcase nm) "SD-*,0,DEFPOINTS,*|*")) (or fade (member (strcase nm) hs)))
          (progn (setq old (cons (list nm (vla-get-Color l) (vla-get-Lineweight l) (if (= (vla-get-LayerOn l) :vlax-true) 1 0)) old))
                 (vl-catch-all-apply '(lambda () (vla-put-Color l 253) (vla-put-Lineweight l 9)) nil)))
        (if (member (strcase nm) hs)
          (progn (if (not (assoc nm old)) (setq old (cons (list nm (vla-get-Color l) (vla-get-Lineweight l) (if (= (vla-get-LayerOn l) :vlax-true) 1 0)) old)))
                 (vl-catch-all-apply 'vla-put-LayerOn (list l :vlax-false)))))
      (vlax-ldata-put "SD" "TRINH-OLD" (cond (old) ((list (list "" 7 -3 1)))))
      (command "_.REGENALL")
      (princ (strcat "\n[SD] Che do trinh khach: lam mo " (itoa (length old)) " layer nen / an. G\\U+00F5 SDTRINH > Tat de tra lai.")))))

(defun sd:tr-off (/ old l)
  (if (setq old (vlax-ldata-get "SD" "TRINH-OLD"))
    (progn
      (foreach o old
        (if (and (/= (car o) "") (tblsearch "LAYER" (car o)))
          (vl-catch-all-apply '(lambda ()
            (setq l (vla-Item (vla-get-Layers (sd:doc)) (car o)))
            (vla-put-Color l (cadr o)) (vla-put-Lineweight l (caddr o)) (vla-put-LayerOn l (if (= (cadddr o) 1) :vlax-true :vlax-false))) nil)))
      (vlax-ldata-delete "SD" "TRINH-OLD")
      (command "_.REGENALL")
      (princ "\n[SD] Da tra lai mau, net va layer nhu cu."))
    (princ "\n[SD] Che do trinh khach chua bat.")))

(defun c:SDTRINH (/ mode rows pt tl)
  (sd:begin)
  (if (sd:dlg "B\\U+1EA3n tr\\U+00ECnh kh\\U+00E1ch (SDTRINH)"
              (list (list "mode" "Vi\\U+1EC7c c\\U+1EA7n l\\U+00E0m" 'kw (sd:cfg "TRINH-MODE" "Chuthich")
                          '(("Chuthich" . "V\\U+1EBD b\\U+1EA3ng ch\\U+00FA th\\U+00EDch v\\U+1EADt li\\U+1EC7u (\\U+00F4 m\\U+1EABu \\U+1EA3nh \\U+0111\\U+00E1)") ("Bat" . "B\\U+1EADt ch\\U+1EBF \\U+0111\\U+1ED9 tr\\U+00ECnh kh\\U+00E1ch") ("Tat" . "T\\U+1EAFt, tr\\U+1EA3 l\\U+1EA1i nh\\U+01B0 c\\U+0169")))
                    (list "tl" "\\U+0110\\U+01A1n v\\U+1ECB b\\U+1EA3n v\\U+1EBD tr\\U+00EAn 1 mm gi\\U+1EA5y (A1 t\\U+1EF7 l\\U+1EC7 1:50 = 50)" 'real (sd:cfg "TRINH-TL" 50.0) nil '("mode" "Chuthich"))
                    (list "an" "Layer \\U+1EA9n khi tr\\U+00ECnh kh\\U+00E1ch (c\\U+00E1ch nhau d\\U+1EA5u ph\\U+1EA9y)" 'str (sd:cfg "TRINH-AN" "SD-CHU") nil '("mode" "Bat"))
                    (list "mo" "L\\U+00E0m m\\U+1EDD c\\U+00E1c layer n\\U+1EC1n ki\\U+1EBFn tr\\U+00FAc (x\\U+00E1m nh\\U+1EA1t, n\\U+00E9t 0,09)" 'tog t nil '("mode" "Bat"))))
    (progn
      (setq mode (sd:cfg-put "TRINH-MODE" (sd:v "mode")))
      (cond
        ((= mode "Chuthich")
         (setq tl (sd:cfg-put "TRINH-TL" (sd:v "tl")) rows (sd:tr-collect))
         (if (null rows)
           (princ "\n[SD] Chua co vien da (SD_TILE) nao: chay SDGACH / SDDOCDA truoc.")
           (if (setq pt (sd:getpt "\nDiem goc tren trai bang chu thich: " nil))
             (princ (strcat "\n[SD] Da ve bang chu thich " (itoa (sd:tr-legend rows (sd:2d pt) tl)) " vat lieu (khung giay 1 mm = " (sd:num tl) " don vi)")))))
        ((= mode "Bat") (sd:tr-on (sd:cfg-put "TRINH-AN" (cond ((sd:v "an")) (""))) (sd:v "mo")))
        (t (sd:tr-off)))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDKHUNGIN - Khung in tu dung: to giay A1 / A3 (A2, A4) o ty le 1:N: khung to (layer SD-KHUNGIN, khong in) lam khung cho SDTAOLAYOUT / SDIN,
;;;  vien trong, khung ten (du an, hang muc, ten ban ve, ty le, ngay, so to), mui ten huong Bac, thuoc ty le; dat san cai dat in
;;;  (SDIN / SDTAOLAYOUT: khung = layer SD-KHUNGIN, net in acad.ctb, vua kho giay, chinh giua; khong in khung anh)
;;;  SDPHUONGAN - Hai phuong an lat A / B tren mot to: nhan phuong an + bang ngan (so vien, nguyen / cat, vien cat hep, hao hut uoc tinh) + khung in bao ca hai
;;; --------------------------------------------------------------------------
(defun sd:khi-paper (kho)
  (cond ((= kho "A1") (list 841.0 594.0)) ((= kho "A2") (list 594.0 420.0)) ((= kho "A4") (list 297.0 210.0)) (t (list 420.0 297.0))))

(defun sd:khi-date (/ d)
  (setq d (rtos (getvar "CDATE") 2 6))
  (strcat (substr d 7 2) "/" (substr d 5 2) "/" (substr d 1 4)))

(defun sd:khi-solid (a b c d lay)
  (entmake (list '(0 . "SOLID") (cons 8 lay) (cons 10 a) (cons 11 b) (cons 12 d) (cons 13 c))))

;; Ve to giay tai goc trai duoi (ox oy): kich thuoc mm giay x k don vi ban ve. Tra ve (w h) don vi ban ve
;; So hieu ban ve: ma-du-an.ma-nha-thau.loai.so (so 2 chu so, tu tang moi lan ve khung neu bat)
(defun sd:khi-num2 (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun sd:khi-sohieu (/ a)
  (setq a (list (sd:cfg "KHI-MADA" "") (sd:cfg "KHI-MANT" "") (sd:cfg "KHI-LOAI" "SDS") (sd:khi-num2 (fix (sd:cfg "KHI-STT" 1)))))
  (sd:join (vl-remove "" a) "."))
(defun sd:khi-hasno () (or (/= (sd:cfg "KHI-MADA" "") "") (/= (sd:cfg "KHI-MANT" "") "")))
;; Cac hang them phia tren khung ten (tu duoi len): ((chu-trai [chu-phai]) ...)
(defun sd:khi-ext (/ r v)
  (if (sd:khi-hasno) (setq r (list (list (strcat "S\\U+1ED0 HI\\U+1EC6U: " (sd:khi-sohieu)) (strcat "REV." (sd:cfg "KHI-REV" "00"))))))
  (foreach kl '(("KHI-NTH" "NG\\U+01AF\\U+1EDCI TH\\U+1EF0C HI\\U+1EC6N") ("KHI-NT" "NH\\U+00C0 TH\\U+1EA6U THI C\\U+00D4NG") ("KHI-TV" "T\\U+01AF V\\U+1EA4N GI\\U+00C1M S\\U+00C1T") ("KHI-CDT" "CH\\U+1EE6 \\U+0110\\U+1EA6U T\\U+01AF"))
    (if (/= (setq v (vl-string-trim " " (sd:cfg (car kl) ""))) "")
      (setq r (append r (list (list (strcat (cadr kl) ": " v)))))))
  r)

(defun sd:khi-draw (kho k ox oy da hm ten ngay so bac thuoc / pp w h lv ll lt bx0 by0 bx1 by1 tbw tx0 cx cy st n i x e r ex ie rw yy)
  (setq pp (sd:khi-paper kho) w (car pp) h (cadr pp)
        lv (sd:make-layer "SD-KHUNGIN-VIEN" 7 "Continuous" 50)
        ll (sd:make-layer "SD-KHUNGIN-LUOI" 7 "Continuous" 25)
        lt (sd:make-layer "SD-KHUNGIN-CHU" 7 "Continuous" 18))
  ;; khung to: dung lam khung in, khong in ra giay
  (sd:make-layer "SD-KHUNGIN" 8 "Continuous" 13)
  (setq r (entget (tblobjname "LAYER" "SD-KHUNGIN")))
  (if (/= (cdr (assoc 290 r)) 0) (entmod (append (vl-remove (assoc 290 r) r) '((290 . 0)))))
  (sd:pline (list (list ox oy) (list (+ ox (* k w)) oy) (list (+ ox (* k w)) (+ oy (* k h))) (list ox (+ oy (* k h)))) t "SD-KHUNGIN")
  (setq bx0 25.0 by0 10.0 bx1 (- w 10.0) by1 (- h 10.0)
        tbw (if (> w 500.0) 180.0 150.0) tx0 (- bx1 tbw))
  (sd:pline (list (list (+ ox (* k bx0)) (+ oy (* k by0))) (list (+ ox (* k bx1)) (+ oy (* k by0)))
                  (list (+ ox (* k bx1)) (+ oy (* k by1))) (list (+ ox (* k bx0)) (+ oy (* k by1)))) t lv)
  ;; khung ten (4 hang: du an, hang muc, ten ban ve, ty le | ngay | so to)
  (sd:pline (list (list (+ ox (* k tx0)) (+ oy (* k by0))) (list (+ ox (* k bx1)) (+ oy (* k by0)))
                  (list (+ ox (* k bx1)) (+ oy (* k (+ by0 40.0)))) (list (+ ox (* k tx0)) (+ oy (* k (+ by0 40.0))))) t lv)
  (foreach dy '(10.0 20.0 30.0)
    (sd:line (list (+ ox (* k tx0)) (+ oy (* k (+ by0 dy)))) (list (+ ox (* k bx1)) (+ oy (* k (+ by0 dy)))) ll))
  (foreach fx '(0.4 0.7)
    (sd:line (list (+ ox (* k (+ tx0 (* tbw fx)))) (+ oy (* k by0))) (list (+ ox (* k (+ tx0 (* tbw fx)))) (+ oy (* k (+ by0 10.0)))) ll))
  (sd:text (list (+ ox (* k (+ tx0 2.0))) (+ oy (* k (+ by0 35.0)))) (strcat "D\\U+1EF0 \\U+00C1N: " da) (* 3.5 k) "ML" lt)
  (sd:text (list (+ ox (* k (+ tx0 2.0))) (+ oy (* k (+ by0 25.0)))) (strcat "H\\U+1EA0NG M\\U+1EE4C: " hm) (* 3.5 k) "ML" lt)
  (sd:text (list (+ ox (* k (+ tx0 2.0))) (+ oy (* k (+ by0 15.0)))) ten (* 5.0 k) "ML" lt)
  (sd:text (list (+ ox (* k (+ tx0 2.0))) (+ oy (* k (+ by0 5.0)))) (strcat "T\\U+1EF6 L\\U+1EC6 1:" (sd:num k)) (* 3.5 k) "ML" lt)
  (sd:text (list (+ ox (* k (+ tx0 (* tbw 0.4) 2.0))) (+ oy (* k (+ by0 5.0)))) (strcat "NG\\U+00C0Y " ngay) (* 3.5 k) "ML" lt)
  (sd:text (list (+ ox (* k (+ tx0 (* tbw 0.7) 2.0))) (+ oy (* k (+ by0 5.0)))) (strcat "T\\U+1EDC " so) (* 3.5 k) "ML" lt)
  ;; cac hang them: so hieu + REV, nguoi thuc hien, nha thau, tu van GS, chu dau tu (chi ve hang co noi dung)
  (setq ex (sd:khi-ext))
  (if ex
    (progn
      (sd:pline (list (list (+ ox (* k tx0)) (+ oy (* k (+ by0 40.0)))) (list (+ ox (* k bx1)) (+ oy (* k (+ by0 40.0))))
                      (list (+ ox (* k bx1)) (+ oy (* k (+ by0 40.0 (* 10.0 (length ex)))))) (list (+ ox (* k tx0)) (+ oy (* k (+ by0 40.0 (* 10.0 (length ex)))))))
                t lv)
      (setq ie 0)
      (foreach rw ex
        (setq yy (+ by0 40.0 (* 10.0 ie)))
        (if (> ie 0) (sd:line (list (+ ox (* k tx0)) (+ oy (* k yy))) (list (+ ox (* k bx1)) (+ oy (* k yy))) ll))
        (sd:text (list (+ ox (* k (+ tx0 2.0))) (+ oy (* k (+ yy 5.0)))) (car rw) (* 3.5 k) "ML" lt)
        (if (cadr rw)
          (progn
            (sd:line (list (+ ox (* k (+ tx0 (* tbw 0.7)))) (+ oy (* k yy))) (list (+ ox (* k (+ tx0 (* tbw 0.7)))) (+ oy (* k (+ yy 10.0)))) ll)
            (sd:text (list (+ ox (* k (+ tx0 (* tbw 0.7) 2.0))) (+ oy (* k (+ yy 5.0)))) (cadr rw) (* 3.5 k) "ML" lt)))
        (setq ie (1+ ie)))))
  (if (and (sd:khi-hasno) (sd:cfg "KHI-TANG" t)) (sd:cfg-put "KHI-STT" (1+ (fix (sd:cfg "KHI-STT" 1)))))
  ;; mui ten huong Bac (tren phai khung)
  (if bac
    (progn
      (setq cx (+ ox (* k (- bx1 20.0))) cy (+ oy (* k (- by1 25.0))))
      (sd:circle (list cx cy) (* 9.0 k) lv)
      (sd:pline (list (list cx (+ cy (* 13.0 k))) (list (+ cx (* 4.0 k)) (- cy (* 6.0 k))) (list cx (- cy (* 2.0 k))) (list (- cx (* 4.0 k)) (- cy (* 6.0 k)))) t lv)
      (sd:text (list cx (+ cy (* 17.0 k))) "N" (* 5.0 k) "MC" lt)))
  ;; thuoc ty le: 5 doan, moi doan st m (1 m neu ty le <= 1:60, 2 m neu <= 1:120, 5 m neu lon hon)
  (if thuoc
    (progn
      (setq st (cond ((<= k 60.0) 1.0) ((<= k 120.0) 2.0) (t 5.0)) n 5 i 0
            x (+ ox (* k (+ bx0 10.0))) cy (+ oy (* k (+ by0 8.0))))
      (sd:text (list x (+ cy (* k 7.0))) (strcat "TH\\U+01AF\\U+1EDAC T\\U+1EF6 L\\U+1EC6 1:" (sd:num k)) (* 3.0 k) "L" lt)
      (repeat n
        (setq e (* st 1000.0))
        (if (= (rem i 2) 0)
          (sd:khi-solid (list x cy) (list (+ x e) cy) (list (+ x e) (+ cy (* 2.0 k))) (list x (+ cy (* 2.0 k))) lv)
          (sd:pline (list (list x cy) (list (+ x e) cy) (list (+ x e) (+ cy (* 2.0 k))) (list x (+ cy (* 2.0 k)))) t lv))
        (sd:text (list x (- cy (* k 3.0))) (sd:num (* i st)) (* 2.5 k) "MC" lt)
        (setq x (+ x e) i (1+ i)))
      (sd:text (list x (- cy (* k 3.0))) (strcat (sd:num (* n st)) " m") (* 2.5 k) "MC" lt)))
  (list (* k w) (* k h)))

(defun sd:khi-put (al k v) (cons (cons k v) (vl-remove (assoc k al) al)))

;; dat san cai dat in cho SDIN / SDTAOLAYOUT: khung = layer SD-KHUNGIN, net in acad.ctb, vua kho giay, chinh giua
(defun sd:khi-preset (tl / a)
  (setq a (vlax-ldata-get "SD" "INHL"))
  (foreach kv (list '("mode" . "Layer") '("key" . "SD-KHUNGIN") '("ctb" . "acad.ctb") '("sc" . "Fit") (cons "center" t))
    (setq a (sd:khi-put a (car kv) (cdr kv))))
  (vlax-ldata-put "SD" "INHL" a)
  (setq a (vlax-ldata-get "SD" "TLO"))
  (foreach kv (list '("mode" . "Layer") '("key" . "SD-KHUNGIN") '("ctb" . "acad.ctb") (cons "sc" (fix tl)))
    (setq a (sd:khi-put a (car kv) (cdr kv))))
  (vlax-ldata-put "SD" "TLO" a)
  (sd:imgframe "Trang"))

(defun c:SDKHUNGIN (/ kho tl pt da hm ten so pp)
  (sd:begin)
  (if (sd:dlg "Khung in (SDKHUNGIN)"
              (list (list "kho" "Kh\\U+1ED5 gi\\U+1EA5y" 'kw (sd:cfg "KHI-KHO" "A1") '(("A1" . "A1 (841 x 594)") ("A3" . "A3 (420 x 297)") ("A2" . "A2 (594 x 420)") ("A4" . "A4 (297 x 210)")))
                    (list "tl" "T\\U+1EF7 l\\U+1EC7 1:" 'real (sd:cfg "KHI-TL" 50.0))
                    (list "da" "D\\U+1EF1 \\U+00E1n" 'str (sd:cfg "KHI-DA" ""))
                    (list "hm" "H\\U+1EA1ng m\\U+1EE5c" 'str (sd:cfg "KHI-HM" ""))
                    (list "ten" "T\\U+00EAn b\\U+1EA3n v\\U+1EBD" 'str (sd:cfg "KHI-TEN" "M\\U+1EB6T B\\U+1EB0NG L\\U+00C1T \\U+0110\\U+00C1"))
                    (list "so" "S\\U+1ED1 t\\U+1EDD (vd 01/03)" 'str (sd:cfg "KHI-SO" "01/01"))
                    (list "cdt" "Ch\\U+1EE7 \\U+0111\\U+1EA7u t\\U+01B0 (tr\\U+1ED1ng = kh\\U+00F4ng ghi)" 'str (sd:cfg "KHI-CDT" ""))
                    (list "tv" "T\\U+01B0 v\\U+1EA5n gi\\U+00E1m s\\U+00E1t (tr\\U+1ED1ng = kh\\U+00F4ng ghi)" 'str (sd:cfg "KHI-TV" ""))
                    (list "nt" "Nh\\U+00E0 th\\U+1EA7u thi c\\U+00F4ng (tr\\U+1ED1ng = kh\\U+00F4ng ghi)" 'str (sd:cfg "KHI-NT" ""))
                    (list "nth" "Ng\\U+01B0\\U+1EDDi th\\U+1EF1c hi\\U+1EC7n (tr\\U+1ED1ng = kh\\U+00F4ng ghi)" 'str (sd:cfg "KHI-NTH" ""))
                    (list "mada" "S\\U+1ED1 hi\\U+1EC7u: m\\U+00E3 d\\U+1EF1 \\U+00E1n (VD C6B)" 'str (sd:cfg "KHI-MADA" ""))
                    (list "mant" "S\\U+1ED1 hi\\U+1EC7u: m\\U+00E3 nh\\U+00E0 th\\U+1EA7u (VD 319)" 'str (sd:cfg "KHI-MANT" ""))
                    (list "loai" "S\\U+1ED1 hi\\U+1EC7u: lo\\U+1EA1i b\\U+1EA3n v\\U+1EBD (VD SDS)" 'str (sd:cfg "KHI-LOAI" "SDS"))
                    (list "stt" "S\\U+1ED1 hi\\U+1EC7u: s\\U+1ED1 th\\U+1EE9 t\\U+1EF1 c\\U+1EE7a b\\U+1EA3n v\\U+1EBD n\\U+00E0y" 'int (fix (sd:cfg "KHI-STT" 1)))
                    (list "rev" "REV (VD 00)" 'str (sd:cfg "KHI-REV" "00"))
                    (list "tang" "T\\U+1EF1 t\\U+0103ng s\\U+1ED1 th\\U+1EE9 t\\U+1EF1 sau m\\U+1ED7i l\\U+1EA7n v\\U+1EBD khung" 'tog (sd:cfg "KHI-TANG" t))
                    (list "bac" "M\\U+0169i t\\U+00EAn h\\U+01B0\\U+1EDBng B\\U+1EAFc" 'tog t)
                    (list "thuoc" "Th\\U+01B0\\U+1EDBc t\\U+1EF7 l\\U+1EC7" 'tog t)
                    (list "cl" "\\U+0110\\U+1EB7t s\\U+1EB5n c\\U+00E0i \\U+0111\\U+1EB7t in cho SDIN / SDTAOLAYOUT (acad.ctb, v\\U+1EEBa kh\\U+1ED5 gi\\U+1EA5y, kh\\U+00F4ng in khung \\U+1EA3nh)" 'tog t)))
    (progn
      (setq kho (sd:cfg-put "KHI-KHO" (sd:v "kho")) tl (sd:cfg-put "KHI-TL" (sd:v "tl"))
            da (sd:cfg-put "KHI-DA" (cond ((sd:v "da")) (""))) hm (sd:cfg-put "KHI-HM" (cond ((sd:v "hm")) (""))) 
            ten (sd:cfg-put "KHI-TEN" (cond ((sd:v "ten")) (""))) so (sd:cfg-put "KHI-SO" (cond ((sd:v "so")) ("")))
            *SD:KHIX* (list (sd:cfg-put "KHI-CDT" (cond ((sd:v "cdt")) (""))) (sd:cfg-put "KHI-TV" (cond ((sd:v "tv")) (""))) (sd:cfg-put "KHI-NT" (cond ((sd:v "nt")) ("")))
                            (sd:cfg-put "KHI-NTH" (cond ((sd:v "nth")) (""))) (sd:cfg-put "KHI-MADA" (vl-string-trim " " (cond ((sd:v "mada")) (""))))
                            (sd:cfg-put "KHI-MANT" (vl-string-trim " " (cond ((sd:v "mant")) (""))))
                            (sd:cfg-put "KHI-LOAI" (vl-string-trim " " (cond ((sd:v "loai")) ("SDS")))) (sd:cfg-put "KHI-STT" (cond ((sd:v "stt")) (1)))
                            (sd:cfg-put "KHI-REV" (cond ((sd:v "rev")) ("00"))) (sd:cfg-put "KHI-TANG" (sd:v "tang")))
            pp (sd:khi-paper kho))
      (if (setq pt (sd:getpt "\nGoc trai duoi cua to giay <0,0>: " nil))
        (progn (sd:khi-draw kho tl (car pt) (cadr pt) da hm ten (sd:khi-date) so (sd:v "bac") (sd:v "thuoc"))
               (if (sd:v "cl") (sd:khi-preset tl))
               (princ (strcat "\n[SD] Da ve khung " kho " ty le 1:" (sd:num tl) " (" (sd:num (* tl (car pp))) " x " (sd:num (* tl (cadr pp))) " don vi)."
                              (if (sd:v "cl") " Cai dat in: SDIN / SDTAOLAYOUT chon khung = layer SD-KHUNGIN (da dat san)." ""))))
        (princ "\n[SD] Chua chon diem."))))
  (sd:finish))

;; Thong ke 1 phuong an tu cac polyline vien SD_TILE: (n nguyen cat dac-biet hep dien-tich hao-hut%) va khung bao
(defun sd:pa-stats (ss hep / i e xd pts nF nC nD nH ar wst nom bb x0 y0 x1 y1)
  (setq i 0 nF 0 nC 0 nD 0 nH 0 ar 0.0 wst 0.0 nom 0.0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) xd (mapcar 'cdr (cdadr (assoc -3 (entget e '("SD_TILE"))))) pts (sd:curve-pts e))
    (if (and (>= (length xd) 12) (/= (nth 1 xd) "X"))
      (progn
        (cond ((= (nth 1 xd) "F") (setq nF (1+ nF))) ((= (nth 1 xd) "C") (setq nC (1+ nC))) (t (setq nD (1+ nD))))
        (if (and (/= (nth 1 xd) "F") (< (min (nth 3 xd) (nth 4 xd)) hep)) (setq nH (1+ nH)))
        (setq ar (+ ar (nth 5 xd)) nom (+ nom (/ (* (nth 8 xd) (nth 9 xd)) 1e6)))
        (if (/= (nth 1 xd) "F") (setq wst (+ wst (max 0.0 (- (/ (* (nth 8 xd) (nth 9 xd)) 1e6) (nth 5 xd))))))
        (setq x0 (cond ((and x0 (< x0 (apply 'min (mapcar 'car pts)))) x0) ((apply 'min (mapcar 'car pts))))
              y0 (cond ((and y0 (< y0 (apply 'min (mapcar 'cadr pts)))) y0) ((apply 'min (mapcar 'cadr pts))))
              x1 (cond ((and x1 (> x1 (apply 'max (mapcar 'car pts)))) x1) ((apply 'max (mapcar 'car pts))))
              y1 (cond ((and y1 (> y1 (apply 'max (mapcar 'cadr pts)))) y1) ((apply 'max (mapcar 'cadr pts))))))))
  (list (list (+ nF nC nD) nF nC nD nH ar (if (> nom 0.0) (* 100.0 (/ wst nom)) 0.0)) (list x0 y0 x1 y1)))

;; Nhan + bang ngan cua 1 phuong an: tieu de tren khung bao, bang duoi khung bao; k = don vi ban ve / 1 mm giay
(defun sd:pa-label (nm st bb k / lay x y lines)
  (setq lay (sd:make-layer "SD-CHUTHICH" 7 "Continuous" 18) x (car bb) y (cadr bb)
        lines (list (strcat "T\\U+1ED5ng: " (itoa (nth 0 st)) " vi\\U+00EAn, " (sd:rtos (nth 5 st) 2) " m\\U+00B2")
                    (strcat "Nguy\\U+00EAn: " (itoa (nth 1 st)) " | C\\U+1EAFt ch\\U+1EEF nh\\U+1EADt: " (itoa (nth 2 st)) " | C\\U+1EAFt \\U+0111\\U+1EB7c bi\\U+1EC7t: " (itoa (nth 3 st)))
                    (strcat "Vi\\U+00EAn c\\U+1EAFt h\\U+1EB9p: " (itoa (nth 4 st)))
                    (strcat "Hao h\\U+1EE5t \\U+01B0\\U+1EDBc t\\U+00EDnh: " (sd:rtos (nth 6 st) 1) " % (ph\\U+1EA7n th\\U+1EEBa c\\U+1EE7a vi\\U+00EAn c\\U+1EAFt)")))
  (sd:text (list x (+ (cadddr bb) (* 6.0 k))) nm (* 6.0 k) "L" lay)
  (setq y (- y (* 6.0 k)))
  (foreach l lines (sd:text (list x y) l (* 3.5 k) "L" lay) (setq y (- y (* 6.0 k)))))

(defun c:SDPHUONGAN (/ kho tl da hm ten hep sa sb ra rb ba bb ux0 uy0 ux1 uy1 pp w h wn hn need ox oy cx cy)
  (sd:begin)
  (if (sd:dlg "Ph\\U+01B0\\U+01A1ng \\U+00E1n A / B (SDPHUONGAN)"
              (list (list "kho" "Kh\\U+1ED5 gi\\U+1EA5y" 'kw (sd:cfg "KHI-KHO" "A1") '(("A1" . "A1 (841 x 594)") ("A3" . "A3 (420 x 297)") ("A2" . "A2 (594 x 420)") ("A4" . "A4 (297 x 210)")))
                    (list "tl" "T\\U+1EF7 l\\U+1EC7 1:" 'real (sd:cfg "KHI-TL" 50.0))
                    (list "da" "D\\U+1EF1 \\U+00E1n" 'str (sd:cfg "KHI-DA" ""))
                    (list "hm" "H\\U+1EA1ng m\\U+1EE5c" 'str (sd:cfg "KHI-HM" ""))
                    (list "ten" "T\\U+00EAn b\\U+1EA3n v\\U+1EBD" 'str "PH\\U+01AF\\U+01A0NG \\U+00C1N L\\U+00C1T \\U+0110\\U+00C1 A / B")
                    (list "hep" "Vi\\U+00EAn c\\U+1EAFt h\\U+1EB9p h\\U+01A1n (mm) t\\U+00EDnh l\\U+00E0 h\\U+1EB9p" 'real (sd:cfg "PA-HEP" 100.0))
                    (list "ve" "V\\U+1EBD lu\\U+00F4n khung in bao c\\U+1EA3 hai ph\\U+01B0\\U+01A1ng \\U+00E1n" 'tog t)))
    (progn
      (setq kho (sd:cfg-put "KHI-KHO" (sd:v "kho")) tl (sd:cfg-put "KHI-TL" (sd:v "tl")) hep (sd:cfg-put "PA-HEP" (sd:v "hep"))
            da (sd:cfg-put "KHI-DA" (cond ((sd:v "da")) (""))) hm (sd:cfg-put "KHI-HM" (cond ((sd:v "hm")) (""))) ten (sd:v "ten"))
      (princ "\nQuet chon cac vi\\U+00EAn c\\U+1EE7a PH\\U+01AF\\U+01A0NG \\U+00C1N A: ")
      (setq sa (ssget '((0 . "LWPOLYLINE") (-3 ("SD_TILE")))))
      (princ "\nQuet chon cac vi\\U+00EAn c\\U+1EE7a PH\\U+01AF\\U+01A0NG \\U+00C1N B: ")
      (setq sb (ssget '((0 . "LWPOLYLINE") (-3 ("SD_TILE")))))
      (if (not (and sa sb))
        (princ "\n[SD] Can chon du hai phuong an (cac vien da dung bang SDGACH / SDDOCDA).")
        (progn
          (setq ra (sd:pa-stats sa hep) rb (sd:pa-stats sb hep) ba (cadr ra) bb (cadr rb) ra (car ra) rb (car rb))
          (sd:pa-label "PH\\U+01AF\\U+01A0NG \\U+00C1N A" ra ba tl)
          (sd:pa-label "PH\\U+01AF\\U+01A0NG \\U+00C1N B" rb bb tl)
          (princ (strcat "\n[SD] A: " (itoa (car ra)) " vien, hao hut uoc tinh " (sd:rtos (nth 6 ra) 1) " % | B: " (itoa (car rb)) " vien, hao hut uoc tinh "
                         (sd:rtos (nth 6 rb) 1) " %."))
          (if (sd:v "ve")
            (progn
              (setq ux0 (min (car ba) (car bb)) uy0 (- (min (cadr ba) (cadr bb)) (* 30.0 tl))
                    ux1 (max (caddr ba) (caddr bb)) uy1 (+ (max (cadddr ba) (cadddr bb)) (* 14.0 tl))
                    pp (sd:khi-paper kho) w (car pp) h (cadr pp)
                    wn (/ (- ux1 ux0) tl) hn (/ (- uy1 uy0) tl))
              (if (or (> wn (- w 45.0)) (> hn (- h 20.0 45.0)))
                (princ (strcat "\n[SD] Hai phuong an khong vua to " kho " ty le 1:" (sd:num tl) " (can ~" (sd:num (fix (+ 1.0 wn))) " x " (sd:num (fix (+ 1.0 hn)))
                               " mm giay, khung ten chiem day to): tang ty le hoac doi kho giay roi chay lai (cac nhan van da ve)."))
                (progn
                  (setq cx (/ (+ ux0 ux1) 2.0) cy (/ (+ uy0 uy1) 2.0)
                        ox (- cx (* tl (/ (+ w 15.0) 2.0))) oy (- cy (* tl (/ (+ h 55.0) 2.0))))
                  (sd:khi-draw kho tl ox oy da hm ten (sd:khi-date) "01/01" t t)
                  (sd:khi-preset tl)
                  (princ (strcat "\n[SD] Da ve khung in " kho " 1:" (sd:num tl) " bao ca hai phuong an; SDIN / SDTAOLAYOUT chon khung = layer SD-KHUNGIN."))))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDBLOCKDA - Block chi tiet da: (Mau) tao block mat cat mui bac 3 bac tu mau co san (Thang / V45 / Roi / CNC, tuy chon hoc LED),
;;;  (Quet) quet hinh bat ky de tao block, (Chen) chen file block .dwg da luu. Tuy chon luu ra .dwg de dung cho ban ve khac
;;;  va mo Block Editor de them thong so dong (Linear + Stretch). Block khong chua polyline vien / anh cat cua SDGACH, SDANHDA...
;;;  (cac lenh quet SDDOCDA, SDANHDA, SDTUDONG, SDRON, SDXOAVIEN khong thay doi tuong nam trong block).
;;; --------------------------------------------------------------------------
(defun sd:bm-since (e0 / e ss)
  (setq e (if e0 (entnext e0) (entnext)))
  (while e (setq ss (cond (ss) ((ssadd))) ss (ssadd e ss) e (entnext e)))
  ss)

(defun sd:bm-name (kieu gd R tm tc nho hoc)
  (strcat "SDCT_" kieu "_" (sd:num gd) "x" (sd:num R) "_t" (sd:num tm) "c" (sd:num tc) "n" (sd:num nho) (if hoc "_LED" "")))

(defun sd:bm-stamp () (substr (vl-string-translate "." "" (rtos (getvar "CDATE") 2 6)) 5))

;; tao block tu ss, goc base; neu ten da co thi hoi ghi de (chi khi hoi = t)
(defun sd:bm-define (name base ss ask / yn)
  (cond
    ((null (tblsearch "BLOCK" name)) (command "_.-BLOCK" name base ss "") t)
    ((and ask (progn (initget "Co Khong")
                     (setq yn (getkword (strcat "\nBlock " name " da co. Ghi de dinh nghia (cac block da chen se doi theo)? [Co/Khong] <Khong>: ")))
                     (= yn "Co")))
     (command "_.-BLOCK" name base ss "_Y" "") t)
    (t nil)))

(defun sd:bm-save (name / f)
  (if (setq f (getfiled "Luu block ra file .dwg (dung cho ban ve khac)" name "dwg" 1))
    (progn
      (if (findfile f) (command "_.-WBLOCK" f "_Y" name) (command "_.-WBLOCK" f name))
      (princ (strcat "\n[SD] Da luu " f)))))

;; Ten cac layer hien co trong ban ve
(defun sd:bm-layers (/ r d)
  (setq d (tblnext "LAYER" T))
  (while d (setq r (cons (cdr (assoc 2 d)) r) d (tblnext "LAYER")))
  r)

;; Don layer cua block vua chen tu file ngoai: dua moi doi tuong trong dinh nghia block (tru layer 0 / DEFPOINTS) ve 1 layer lay,
;; roi xoa cac layer moi do file mang vao (old = danh sach layer truoc khi chen). Tra ve (so-doi-tuong so-layer-xoa)
(defun sd:bm-clean (bn lay old / e ed n nd nm)
  (sd:make-layer lay 7 "Continuous" 18)
  (setq e (cdr (assoc -2 (tblsearch "BLOCK" bn))) n 0 nd 0)
  (while e
    (setq ed (entget e))
    (if (and (assoc 8 ed) (not (member (strcase (cdr (assoc 8 ed))) (list "0" "DEFPOINTS" (strcase lay)))))
      (progn (entmod (subst (cons 8 lay) (assoc 8 ed) ed)) (setq n (1+ n))))
    (setq e (entnext e)))
  (foreach nm (sd:bm-layers)
    (if (and (not (member nm old)) (/= (strcase nm) (strcase lay)))
      (if (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-Delete (list (vla-Item (vla-get-Layers (sd:doc)) nm)))))
        (setq nd (1+ nd)))))
  (list n nd))

;; Mat cat chi tiet op kho (da treo tren khung thep): tuong ben trai, 2 tam da chong len nhau co khe joint, bat treo inox + moc treo inox o cao do khe,
;; thep L, bulong no. Ve 1:1 (mm) tai goc (0,0); tam duoi y 0..hh. t day da, g khe lung da - tuong, j khe joint, c vat canh (0 = thang),
;; la canh thep L, lt day thep L, bd duong kinh bulong, bl chieu dai bulong. So lieu mac dinh chi la mau minh hoa: kiem tra voi phu kien thuc te.
(defun sd:bm-opkho (dd g j c la lt bd bl hh / x1 yj yb yc xc th lbl)
  (sd:make-layer "SD-GACH" 7 "Continuous" 25) (sd:make-layer "SD-GACH-CAT" 4 "Continuous" 25) (sd:make-layer "SD-KHUAT" 8 "Continuous" 13)
  (sd:make-layer "SD-CHU" 7 "Continuous" 18)
  (setq x1 (+ g dd) yj (+ hh (/ j 2.0)) yb (- yj lt (/ la 2.0)) yc (+ yb (/ la 2.0)) xc (+ g (/ dd 2.0)) th 8.0)
  ;; tuong
  (sd:pline (list (list -150.0 -80.0) (list 0.0 -80.0) (list 0.0 (+ (* 2.0 hh) j 80.0)) (list -150.0 (+ (* 2.0 hh) j 80.0))) t "SD-KHUAT")
  ;; tam da duoi va tren (vat canh phia khe joint neu c > 0)
  (sd:pline (if (> c 0.0)
              (list (list g 0.0) (list x1 0.0) (list x1 (- hh c)) (list (- x1 c) hh) (list g hh))
              (list (list g 0.0) (list x1 0.0) (list x1 hh) (list g hh)))
            t "SD-GACH")
  (sd:pline (if (> c 0.0)
              (list (list g (+ hh j)) (list (- x1 c) (+ hh j)) (list x1 (+ hh j c)) (list x1 (+ (* 2.0 hh) j)) (list g (+ (* 2.0 hh) j)))
              (list (list g (+ hh j)) (list x1 (+ hh j)) (list x1 (+ (* 2.0 hh) j)) (list g (+ (* 2.0 hh) j))))
            t "SD-GACH")
  ;; thep L: canh dung sat tuong, canh ngang nam duoi bat treo
  (sd:pline (list (list 0.0 yb) (list la yb) (list la (+ yb lt)) (list lt (+ yb lt)) (list lt (+ yb la)) (list 0.0 (+ yb la))) t "SD-GACH-CAT")
  ;; bulong no xuyen canh dung (dau bulong ben ngoai)
  (sd:pline (list (list (- bl) (- yc (/ bd 2.0))) (list lt (- yc (/ bd 2.0))) (list lt (+ yc (/ bd 2.0))) (list (- bl) (+ yc (/ bd 2.0)))) t "SD-GACH-CAT")
  (sd:pline (list (list lt (- yc (* 0.9 bd))) (list (+ lt 5.0) (- yc (* 0.9 bd))) (list (+ lt 5.0) (+ yc (* 0.9 bd))) (list lt (+ yc (* 0.9 bd)))) t "SD-GACH-CAT")
  ;; bat treo inox: ban dua nam tren canh ngang thep L, voi toi giua day da
  (sd:pline (list (list (/ la 2.0) (+ yb lt)) (list (+ xc 10.0) (+ yb lt)) (list (+ xc 10.0) (+ yb lt 3.0)) (list (/ la 2.0) (+ yb lt 3.0))) t "SD-GACH-CAT")
  ;; moc treo inox: chot dung xuyen ban dua, cam vao canh tam duoi va tam tren
  (sd:pline (list (list (- xc 2.0) (- hh 15.0)) (list (+ xc 2.0) (- hh 15.0)) (list (+ xc 2.0) (+ hh j 15.0)) (list (- xc 2.0) (+ hh j 15.0))) t "SD-GACH-CAT")
  ;; chu thich
  (setq lbl (+ x1 80.0))
  (sd:line (list xc (/ hh 2.0)) (list lbl (/ hh 2.0)) "SD-CHU")
  (sd:text (list (+ lbl 5.0) (/ hh 2.0)) (strcat "\\U+0110\\U+00C1 GRANIT D\\U+00C0Y " (sd:num dd)) th "ML" "SD-CHU")
  (sd:line (list x1 yj) (list lbl yj) "SD-CHU")
  (sd:text (list (+ lbl 5.0) yj) (strcat "KHE JOINT " (sd:num j) (if (> c 0.0) (strcat ", V\\U+00C1T C\\U+1EA0NH " (sd:num c) " x 45\\U+00B0") ", TH\\U+1EB2NG")) th "ML" "SD-CHU")
  (sd:line (list xc (+ hh j 15.0)) (list lbl (+ hh j 45.0)) "SD-CHU")
  (sd:text (list (+ lbl 5.0) (+ hh j 45.0)) "M\\U+00D3C TREO INOX" th "ML" "SD-CHU")
  (setq lbl (- (- bl) 40.0))
  (sd:line (list (- (/ bl 2.0)) yc) (list lbl yc) "SD-CHU")
  (sd:text (list (- lbl 5.0) yc) (strcat "BUL\\U+00D4NG N\\U+1EDE INOX M" (sd:num bd) "x" (sd:num bl)) th "MR" "SD-CHU")
  (sd:line (list (/ la 2.0) (+ yb lt 1.5)) (list lbl (+ yb lt 40.0)) "SD-CHU")
  (sd:text (list (- lbl 5.0) (+ yb lt 40.0)) "B\\U+00C1T TREO INOX" th "MR" "SD-CHU")
  (sd:line (list (/ lt 2.0) (+ yb la)) (list lbl (- yb 40.0)) "SD-CHU")
  (sd:text (list (- lbl 5.0) (- yb 40.0)) (strcat "TH\\U+00C9P L" (sd:num la) "x" (sd:num la) "x" (sd:num lt)) th "MR" "SD-CHU")
  (sd:text (list (- lbl 5.0) (/ hh 2.0)) "T\\U+01AF\\U+1EDCNG / K\\U+1EBET C\\U+1EA4U" th "MR" "SD-CHU")
  t)

(defun c:SDBLOCKDA (/ mode kieu gd R tm tc nho hoc name e0 ss base pt keep wb dyn ok f ents n don laych bn nuevo old ot og oj oc ol olt obd obl ohh)
  (sd:begin)
  (if (sd:dlg "Block chi tiet da (SDBLOCKDA)"
              (list (list "mode" "Viec can lam" 'kw (sd:cfg "BLK-MODE" "Mau")
                          '(("Mau" . "Tao block mat cat mui bac tu mau co san")
                            ("Quet" . "Quet hinh bat ky de tao block")
                            ("Chen" . "Chen file block .dwg da luu")
                            ("Opkho" . "Chi tiet op kho: da treo tren khung thep, joint vat canh")))
                    (list "kieu" "Kieu mui bac" 'kw (sd:cfg "BLK-KIEU" "Thang")
                          '(("Thang" . "Thang (mat chong len co, mui nho ra)") ("V45" . "Ghep vat 45 do") ("Roi" . "Dai mui roi") ("CNC" . "Mui bo / vat CNC"))
                          '("mode" "Mau"))
                    (list "gd" "Mat bac rong (mm)" 'real (sd:cfg "BLK-GD" 300.0) nil '("mode" "Mau"))
                    (list "R" "Cao bac (mm)" 'real (sd:cfg "BLK-R" 150.0) nil '("mode" "Mau"))
                    (list "tm" "Day mat bac (mm)" 'real (sd:cfg "BLK-TM" 20.0) nil '("mode" "Mau"))
                    (list "tc" "Day co bac (mm)" 'real (sd:cfg "BLK-TC" 20.0) nil '("mode" "Mau"))
                    (list "nho" "Mui nho ra (mm)" 'real0 (sd:cfg "BLK-NHO" 20.0) nil '("mode" "Mau"))
                    (list "hoc" "Co hoc LED duoi mep truoc mat bac (17 x 20, cach mep 20)" 'tog nil nil '("mode" "Mau"))
                    (list "ot" "Day da (mm)" 'real (sd:cfg "OK-T" 20.0) nil '("mode" "Opkho"))
                    (list "og" "Khe tu lung da den tuong (mm)" 'real (sd:cfg "OK-G" 40.0) nil '("mode" "Opkho"))
                    (list "oj" "Khe joint giua hai tam (mm)" 'real (sd:cfg "OK-J" 8.0) nil '("mode" "Opkho"))
                    (list "oc" "Vat canh phia mat khe joint (mm, 0 = joint thang)" 'real0 (sd:cfg "OK-C" 3.0) nil '("mode" "Opkho"))
                    (list "ol" "Thep L: canh (mm)" 'real (sd:cfg "OK-L" 30.0) nil '("mode" "Opkho"))
                    (list "olt" "Thep L: day (mm)" 'real (sd:cfg "OK-LT" 3.0) nil '("mode" "Opkho"))
                    (list "obd" "Bulong no: duong kinh (mm)" 'real (sd:cfg "OK-BD" 8.0) nil '("mode" "Opkho"))
                    (list "obl" "Bulong no: chieu dai (mm)" 'real (sd:cfg "OK-BL" 100.0) nil '("mode" "Opkho"))
                    (list "ohh" "Chieu cao moi tam ve (mm)" 'real (sd:cfg "OK-H" 600.0) nil '("mode" "Opkho"))
                    (list "keep" "Giu hinh tren ban ve (chen lai thanh block)" 'tog t nil '("mode" "Quet"))
                    (list "wb" "Luu ra file .dwg de dung cho ban ve khac" 'tog nil nil '("mode" "Mau" "Quet" "Opkho"))
                    (list "dyn" "Mo Block Editor de them thong so dong (Linear + Stretch)" 'tog nil nil '("mode" "Mau" "Quet" "Opkho"))
                    (list "don" "Layer cua block tai tu ngoai" 'kw (sd:cfg "BLK-DON" "Gop")
                          '(("Gop" . "Don: dua moi doi tuong ve 1 layer, xoa layer la file mang vao") ("Giu" . "Giu nguyen layer cua file"))
                          '("mode" "Chen"))
                    (list "laych" "Ten layer chung cho block chen" 'str (sd:cfg "BLK-LAY" "SD-CHITIET") nil '("mode" "Chen"))))
    (progn
      (setq mode (sd:cfg-put "BLK-MODE" (sd:v "mode")))
      (cond
        ;; ---- mau mui bac
        ((= mode "Mau")
         (setq kieu (sd:cfg-put "BLK-KIEU" (sd:v "kieu")) gd (sd:cfg-put "BLK-GD" (sd:v "gd")) R (sd:cfg-put "BLK-R" (sd:v "R"))
               tm (sd:cfg-put "BLK-TM" (sd:v "tm")) tc (sd:cfg-put "BLK-TC" (sd:v "tc")) nho (sd:cfg-put "BLK-NHO" (cond ((sd:v "nho")) (0.0)))
               hoc (sd:v "hoc") wb (sd:v "wb") dyn (sd:v "dyn")
               name (sd:bm-name kieu gd R tm tc nho hoc))
         (if (tblsearch "BLOCK" name)
           (princ (strcat "\n[SD] Block " name " da co: dung lai."))
           (progn
             (sd:make-layer "SD-GACH" 7 "Continuous" 25) (sd:make-layer "SD-GACH-CAT" 4 "Continuous" 25) (sd:make-layer "SD-KHUAT" 8 "Continuous" 13)
             (setq e0 (entlast))
             (sd:st-profile (list 0.0 0.0 0.0) kieu gd R tm tc nho 30.0 0.0 (if hoc "Hoc" "Khong") 17.0 20.0 20.0)
             (if (setq ss (sd:bm-since e0))
               (progn (sd:bm-define name (list 0.0 0.0 0.0) ss nil)
                      (princ (strcat "\n[SD] Da tao block " name " (mat cat 3 bac, goc tai mui bac dau, mat chieu nghi duoi).")))
               (princ "\n[SD] Khong ve duoc mau."))))
         (if (tblsearch "BLOCK" name)
           (progn
             (if (setq pt (sd:getpt "\nDiem chen block <Enter = chi tao khong chen>: " nil))
               (command "_.-INSERT" name (list (car pt) (cadr pt) 0.0) "1" "1" "0"))
             (if wb (sd:bm-save name))
             (if dyn (command "_.BEDIT" name)))))
        ;; ---- chi tiet op kho
        ((= mode "Opkho")
         (setq ot (sd:cfg-put "OK-T" (sd:v "ot")) og (sd:cfg-put "OK-G" (sd:v "og")) oj (sd:cfg-put "OK-J" (sd:v "oj"))
               oc (sd:cfg-put "OK-C" (cond ((sd:v "oc")) (0.0))) ol (sd:cfg-put "OK-L" (sd:v "ol")) olt (sd:cfg-put "OK-LT" (sd:v "olt"))
               obd (sd:cfg-put "OK-BD" (sd:v "obd")) obl (sd:cfg-put "OK-BL" (sd:v "obl")) ohh (sd:cfg-put "OK-H" (sd:v "ohh"))
               wb (sd:v "wb") dyn (sd:v "dyn")
               name (strcat "SDCT_OPKHO_t" (sd:num ot) "g" (sd:num og) "j" (sd:num oj) "c" (sd:num oc) "L" (sd:num ol) "x" (sd:num olt) "M" (sd:num obd) "x" (sd:num obl)))
         (if (tblsearch "BLOCK" name)
           (princ (strcat "\n[SD] Block " name " da co: dung lai."))
           (progn
             (setq e0 (entlast))
             (sd:bm-opkho ot og oj oc ol olt obd obl ohh)
             (if (setq ss (sd:bm-since e0))
               (progn (sd:bm-define name (list 0.0 0.0 0.0) ss nil)
                      (princ (strcat "\n[SD] Da tao block " name " (mat cat 1:1 mm, goc tai mat tuong o duoi tam da duoi). So lieu phu kien la mau minh hoa: doi chieu voi phu kien thuc te truoc khi dung.")))
               (princ "\n[SD] Khong ve duoc chi tiet."))))
         (if (tblsearch "BLOCK" name)
           (progn
             (if (setq pt (sd:getpt "\nDiem chen block <Enter = chi tao khong chen>: " nil))
               (command "_.-INSERT" name (list (car pt) (cadr pt) 0.0) "1" "1" "0"))
             (if wb (sd:bm-save name))
             (if dyn (command "_.BEDIT" name)))))
        ;; ---- quet hinh
        ((= mode "Quet")
         (setq keep (sd:v "keep") wb (sd:v "wb") dyn (sd:v "dyn"))
         (princ "\nQuet chon hinh de tao block (lenh nay khong dung cho cac vien da dung bang SDGACH / SDANHDA: do la nhieu doi tuong lien ket): ")
         (if (setq ss (ssget))
           (if (setq base (getpoint "\nDiem goc (diem chen) cua block: "))
             (progn
               (setq name (getstring T "\nTen block <tu dat>: "))
               (if (or (null name) (= name "")) (setq name (strcat "SDCT_Q" (sd:bm-stamp))))
               (if (sd:bm-define name (list (car base) (cadr base) 0.0) ss t)
                 (progn
                   (if keep (command "_.-INSERT" name (list (car base) (cadr base) 0.0) "1" "1" "0"))
                   (princ (strcat "\n[SD] Da tao block " name "."))
                   (if wb (sd:bm-save name))
                   (if dyn (command "_.BEDIT" name)))
                 (princ "\n[SD] Giu nguyen, khong tao block."))))))
        ;; ---- chen file
        (t
         (setq don (sd:cfg-put "BLK-DON" (sd:v "don")) laych (sd:cfg-put "BLK-LAY" (cond ((sd:v "laych")) ("SD-CHITIET"))))
         (if (setq f (getfiled "Chon file block (.dwg) de chen" "" "dwg" 4))
           (if (setq pt (sd:getpt "\nDiem chen block: " nil))
             (progn
               (setq nuevo (not (tblsearch "BLOCK" (vl-filename-base f))) old (sd:bm-layers))
               (command "_.-INSERT" (vl-string-translate "\\" "/" f) (list (car pt) (cadr pt) 0.0) "1" "1" "0")
               (princ "\n[SD] Da chen block.")
               (if (and nuevo (= don "Gop") (setq e0 (entlast)) (= (cdr (assoc 0 (entget e0))) "INSERT"))
                 (progn
                   (setq bn (cdr (assoc 2 (entget e0))) n (sd:bm-clean bn laych old))
                   (princ (strcat "\n[SD] Don layer: " (itoa (car n)) " doi tuong ve layer " laych ", xoa " (itoa (cadr n)) " layer la.")))))))))))
  (sd:finish))

;;; --------------------------------------------------------------------------
;;;  SDTUNAP - tu nap SDOpLat.lsp moi khi mo AutoCAD (khong can APPLOAD lai):
;;;  ghi mot khoi co danh dau vao acaddoc.lsp trong thu muc Support cua nguoi dung; chay lai de go
;;; --------------------------------------------------------------------------
(defun sd:au-file () (strcat (getvar "ROAMABLEROOTPREFIX") "Support\\acaddoc.lsp"))

(defun sd:au-read (f / h l r)
  (if (and (findfile f) (setq h (open f "r")))
    (progn (while (setq l (read-line h)) (setq r (cons l r))) (close h)))
  (reverse r))

;; bo khoi SDOpLat (giua hai dong danh dau) khoi danh sach dong
(defun sd:au-strip (lines / r in)
  (foreach l lines
    (cond ((wcmatch l ";;; SD-AUTOLOAD-BEGIN*") (setq in t))
          ((wcmatch l ";;; SD-AUTOLOAD-END*") (setq in nil))
          (in)
          (t (setq r (cons l r)))))
  (reverse r))

(defun sd:au-has (lines) (vl-some '(lambda (l) (wcmatch l ";;; SD-AUTOLOAD-BEGIN*")) lines))

(defun sd:au-write (f lines / h)
  (if (setq h (open f "w"))
    (progn (foreach l lines (write-line l h)) (close h) t)))

(defun c:SDTUNAP (/ f lines lsp tp ans)
  (sd:begin)
  (setq f (sd:au-file) lines (sd:au-read f))
  (cond
    ((sd:au-has lines)
     (initget "Giu Go")
     (setq ans (getkword "\nSDOpLat dang tu nap moi khi mo AutoCAD. [Giu/Go] <Giu>: "))
     (if (= ans "Go")
       (if (sd:au-write f (sd:au-strip lines))
         (princ "\n[SD] Da go tu nap. Lan sau mo AutoCAD phai APPLOAD hoac SDMENU.")
         (princ (strcat "\n[SD] Khong ghi duoc " f)))
       (princ "\n[SD] Giu nguyen tu nap.")))
    (t
     (setq lsp (cond ((findfile "SDOpLat.lsp"))
                     ((getfiled "Chon SDOpLat.lsp (cho tu nap)" "" "lsp" 4))))
     (if (null lsp)
       (princ "\n[SD] Chua chon file SDOpLat.lsp.")
       (progn
         (setq lsp (vl-string-translate "\\" "/" lsp))
         (if (sd:au-write f
               (append (sd:au-strip lines)
                       (list ";;; SD-AUTOLOAD-BEGIN - SDOpLat Tools tu nap (SDTUNAP, go bang SDTUNAP > Go)"
                             (strcat "(if (and (not c:SDHELP) (findfile \"" lsp "\")) (load \"" lsp "\"))")
                             ";;; SD-AUTOLOAD-END")))
           (progn
             ;; thu muc tin cay de AutoCAD khong hoi / chan khi nap
             (setq tp (getvar "TRUSTEDPATHS"))
             (if (and tp (not (vl-string-search (strcase (vl-filename-directory lsp)) (strcase (vl-string-translate "\\" "/" tp)))))
               (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" (strcat tp ";" (vl-filename-directory lsp)))))
             (princ (strcat "\n[SD] Da bat tu nap: " lsp "\n   Moi lan mo AutoCAD / ban ve moi se tu nap, khong can APPLOAD. Dung doi cho / xoa thu muc SDOpLat."
                            "\n   Ten thu muc nen la chu khong dau. Go bang SDTUNAP > Go.")))
           (princ (strcat "\n[SD] Khong ghi duoc " f " - chay AutoCAD voi quyen ghi thu muc Support, hoac dung SDMENU.")))))))
  (sd:finish))

(defun sd:add-path (dir / fl sp tp)
  (setq fl (vla-get-Files (vla-get-Preferences (vlax-get-acad-object))) sp (vla-get-SupportPath fl))
  (if (not (vl-string-search (strcase dir) (strcase sp)))
    (vla-put-SupportPath fl (strcat sp ";" dir)))
  ;; AutoCAD 2014+: thu muc tin cay de nap LSP/MNL khong bi canh bao
  (if (and (setq tp (vl-catch-all-apply 'getvar '("TRUSTEDPATHS"))) (= (type tp) 'STR)
           (not (vl-string-search (strcase dir) (strcase tp))))
    (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" (if (= tp "") dir (strcat tp ";" dir))))))

(defun sd:rx-off ()
  (foreach v '(*SD:TM-CR* *SD:TM-LR*)
    (if (and (boundp v) (eval v)) (vl-catch-all-apply 'vlr-remove (list (eval v)))))
  (setq *SD:TM-CR* nil *SD:TM-LR* nil))

;; SDMENU: nap menu / Ribbon bang COM (AcadMenuGroups.Load / Unload): khong qua dong lenh nen duong dan co dau cach,
;; chu co dau van dung (SendCommand tach duong dan tai dau cach). Du phong: SendCommand co dau nhay quanh duong dan.
(defun sd:mg-find (grp / mgs r)
  (setq mgs (vla-get-MenuGroups (vlax-get-acad-object)) r (vl-catch-all-apply 'vla-Item (list mgs grp)))
  (if (vl-catch-all-error-p r) nil r))

(defun sd:mg-load (fn grp / mgs g r)
  (setq mgs (vla-get-MenuGroups (vlax-get-acad-object)))
  (if (setq g (sd:mg-find grp)) (vl-catch-all-apply 'vla-Unload (list g)))
  (setq r (vl-catch-all-apply 'vla-Load (list mgs fn)))
  (if (vl-catch-all-error-p r)
    (progn
      (vla-SendCommand (sd:doc) (strcat "_.CUILOAD\n\"" fn "\"\n"))
      (princ (strcat "\n[SD] Nap '" grp "' bang lenh CUILOAD (COM loi: " (vl-catch-all-error-message r) ")."))
      nil)
    t))

;; Phien ban ghi trong dong dau cua file .mnu ("//  Op Lat Tools vX.Y.Z ..."), nil neu khong co (ban cu)
(defun sd:mnu-ver (f / h l r k)
  (if (and f (setq h (open f "r")))
    (progn
      (repeat 8
        (if (and (null r) (setq l (read-line h)) (setq k (vl-string-search "Tools v" l)))
          (setq r (car (sd:split (substr l (+ k 8)) " ")))))
      (close h)))
  r)

;; Moi file SDOpLat.mnu tren duong dan tim kiem cua AutoCAD (moi thu muc da tung SDMENU / them vao duong dan deu duoc liet ke)
(defun sd:mnu-cands (/ r d)
  (foreach p (append (sd:split (cond ((getenv "ACAD")) ("")) ";") (list (cond ((getvar "DWGPREFIX")) (""))))
    (if (and (/= p "") (setq d (findfile (strcat (vl-string-right-trim "\\" p) "\\SDOpLat.mnu"))) (not (member d r)))
      (setq r (cons d r))))
  (if (and (setq d (findfile "SDOpLat.mnu")) (not (member d r))) (setq r (cons d r)))
  (reverse r))

;; Dua pull-down "SDOpLat" cua nhom menu grp len thanh menu neu chua co (CUILOAD khong luon tu them vao workspace dang dung).
;; Tra ve "them" / "co" / "khong-thay-popup"
(defun sd:menu-bar (grp / mg menus bar pm found)
  (setq mg (sd:mg-find grp))
  (if mg
    (progn
      (setq menus (vla-get-Menus mg) bar (vla-get-MenuBar (vlax-get-acad-object)))
      (vlax-for m menus (if (and (null pm) (wcmatch (strcase (vla-get-Name m)) "*SDOPLAT*")) (setq pm m)))
      (if pm
        (progn
          (vlax-for b bar (if (wcmatch (strcase (vla-get-Name b)) "*SDOPLAT*") (setq found t)))
          (if found
            "co"
            (progn (vla-InsertInMenuBar pm (vla-get-Count bar)) "them")))
        "khong-thay-popup"))))

(defun c:SDMENU (/ mnu dir rb ok1 ok2 r cands ver f mb)
  (princ (strcat "\n[SD] SDMENU v" *SD:VER*))
  (sd:rx-off)
  (setq r (vl-catch-all-apply
            '(lambda ()
               ;; chon file .mnu dung phien ban dang chay: cac ban cu con nam tren duong dan tim kiem se khong bi nap nham
               (setq cands (sd:mnu-cands))
               (foreach f cands (if (and (null mnu) (= (sd:mnu-ver f) *SD:VER*)) (setq mnu f)))
               (if (null mnu)
                 (progn
                   (if cands
                     (progn
                       (princ (strcat "\n[SD] Khong thay SDOpLat.mnu phien ban " *SD:VER* " tren duong dan tim kiem. Cac file tim thay:"))
                       (foreach f cands (princ (strcat "\n     " f "  (ban " (cond ((sd:mnu-ver f)) ("cu, khong ghi phien ban")) ")")))
                       (princ "\n     Chon file SDOpLat.mnu trong thu muc ban vua giai nen (cung thu muc voi SDOpLat.lsp ban dang nap).")))
                   (setq mnu (getfiled "Chon file SDOpLat.mnu (thu muc ban moi giai nen)" (cond ((car cands) (vl-filename-directory (car cands))) ((getvar "DWGPREFIX"))) "mnu" 0))))
               (if mnu
                 (progn
                   (setq dir (vl-filename-directory mnu)
                         rb (findfile (strcat dir "\\SDOpLatRibbon.cuix")))
                   (vl-catch-all-apply 'sd:add-path (list dir))
                   ;; xoa ban .cuix / .mns da chuyen doi tu .mnu cu (de AutoCAD chuyen lai tu .mnu moi)
                   (foreach ext '("cuix" "mns" "mnc" "mnr")
                     (setq f (strcat dir "\\SDOpLat." ext))
                     (if (findfile f) (vl-catch-all-apply 'vl-file-delete (list f))))
                   (setq ver (sd:mnu-ver mnu))
                   (if (/= ver *SD:VER*)
                     (princ (strcat "\n[!] File menu nap la ban " (cond (ver) ("cu, khong ghi phien ban")) " nhung SDOpLat.lsp dang chay la ban " *SD:VER*
                                    ": lenh moi co the thieu tren menu. Giai nen ban moi vao thu muc rieng roi chay lai SDMENU.")))
                   (setq ok1 (sd:mg-load mnu "SDOPLAT"))
                   (if ok1
                     (progn
                       (setq mb (vl-catch-all-apply 'sd:menu-bar (list "SDOPLAT")))
                       (princ (cond ((vl-catch-all-error-p mb)
                                     (strcat "\n[SD] Khong them duoc menu SDOpLat vao thanh menu (" (vl-catch-all-error-message mb)
                                             "). Them tay: CUI > Workspaces > (workspace dang dung) > Customize Workspace > tich SDOpLat."))
                                    ((= mb "them") "\n[SD] Da them menu SDOpLat vao thanh menu.")
                                    ((= mb "co") "\n[SD] Menu SDOpLat da co tren thanh menu.")
                                    (t "\n[SD] Khong thay pull-down SDOpLat trong nhom menu da nap.")))))
                   (if rb (setq ok2 (sd:mg-load rb "SDOPLATRIBBON")))
                   (princ (strcat "\n[SD] " (if ok1 "Da nap menu + toolbar" "Chua nap duoc menu")
                                  (if rb (if ok2 " + Ribbon" ", chua nap duoc Ribbon") ", khong thay file Ribbon") " tu " dir))
                   (if ok2 (princ "\n     Neu khong thay tab Ribbon: nhap phai vung Ribbon -> Show Tabs -> tich SDOpLat."))))
               nil)
            nil))
  (if (vl-catch-all-error-p r)
    (princ (strcat "\n[SD] Khong nap duoc menu: " (vl-catch-all-error-message r)
                   "\n     Nap tay: CUILOAD -> SDOpLat.mnu va SDOpLatRibbon.cuix (thu muc dist).")))
  
  (princ))

(defun c:SDMENUXOA (/ yn)
  (initget "Co Khong")
  (setq yn (cond ((getkword "\nGo menu, toolbar va Ribbon SDOpLat [Co/Khong] <Khong>: ")) ("Khong")))
  (if (= yn "Co") (sd:menu-unload) (princ "\n[SD] Khong go menu."))
  (princ))

(defun sd:menu-unload (/ g)
  (foreach grp '("SDOPLATRIBBON" "SDOPLAT")
    (if (setq g (sd:mg-find grp))
      (progn (vl-catch-all-apply 'vla-Unload (list g))
             (princ (strcat "\n[SD] Da go " grp ".")))
      (princ (strcat "\n[SD] " grp " chua duoc nap.")))))
(vl-catch-all-apply 'sd:ud-autoload nil)

(princ (strcat "\n[SD] Op Lat Tools v" *SD:VER* " da nap. Go SDPANEL (bang lenh) hoac SDHELP; SDMENU de cai menu + toolbar."))
(if (not (vl-catch-all-error-p (vl-catch-all-apply '(lambda () (sd:au-has (sd:au-read (sd:au-file)))) nil)))
  (if (not (sd:au-has (sd:au-read (sd:au-file))))
    (princ "\n[SD] Chua tu nap moi khi mo AutoCAD: go SDTUNAP mot lan (hoac SDMENU).")))
(princ)
