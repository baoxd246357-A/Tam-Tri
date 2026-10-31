;;; ==========================================================================
;;;  KICH HOAT BAN QUYEN THEO MAY (SDKICHHOAT)
;;;  Khach gui "Ma may" cho nha cung cap, nhan lai "Ma kich hoat" chi dung duoc tren dung may do.
;;;  Cac lenh chinh chi chay khi da kich hoat; SDKICHHOAT, SDHELP, SDPANEL, SDMENU, SDMENUXOA, SDTUNAP, SDDLG luon chay.
;;; ==========================================================================
(setq *SD:LICSECRET* "@@SECRET@@")
(setq *SD:LICABC* "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
(setq *SD:LICREG* "HKEY_CURRENT_USER\\Software\\SDOpLat")
(setq *SD:LICOK* nil *SD:LICMID* nil *SD:LICTRIAL* @@TRIAL@@)

;; AutoLISP khong co LOGXOR: a xor b = (a or b) - (a and b) voi so khong am
(defun sd:lic-xor (a b) (- (logior a b) (logand a b)))

(defun sd:lic-setnth (l k v / i r)
  (setq i 0)
  (foreach x l (setq r (cons (if (= i k) v x) r) i (1+ i)))
  (reverse r))

;; Bam chuoi s thanh 4 so 24 bit (chi dung so < 2^30 de khong tran so nguyen 32 bit cua AutoLISP)
(defun sd:lic-hash (s / h m n i c k pv)
  (setq h '(5381 52711 40503 12289) m '(31 33 37 41) n (strlen s))
  (repeat 2
    (setq i 1)
    (while (<= i n)
      (setq c (ascii (substr s i 1)) k 0)
      (while (< k 4)
        (setq pv (logand (lsh (nth (rem (+ k 3) 4) h) -5) 255)
              h  (sd:lic-setnth h k (logand (sd:lic-xor (+ (* (nth k h) (nth k m)) c pv (rem i 251)) (lsh (nth k h) -9)) 16777215))
              k  (1+ k)))
      (setq i (1+ i))))
  h)

;; n ky tu moi lane (4 lane) -> chuoi chu so / chu (bang chu cai khong co I O 0 1)
(defun sd:lic-chars (h counts / r i j)
  (setq i 0 r "")
  (foreach cnt counts
    (setq j 0)
    (while (< j cnt)
      (setq r (strcat r (substr *SD:LICABC* (1+ (logand (lsh (nth i h) (* -5 j)) 31)) 1)) j (1+ j)))
    (setq i (1+ i)))
  r)

(defun sd:lic-code (s / r)
  (setq r (sd:lic-chars (sd:lic-hash s) '(4 4 4 3)))
  (strcat (substr r 1 5) "-" (substr r 6 5) "-" (substr r 11 5)))

(defun sd:lic-mid-of (raw / r)
  (setq r (sd:lic-chars (sd:lic-hash raw) '(3 3 3 3)))
  (strcat (substr r 1 4) "-" (substr r 5 4) "-" (substr r 9 4)))

;; Chi giu chu va so, viet hoa
(defun sd:lic-norm (s / r i c)
  (setq r "" i 1 s (strcase (cond (s) (""))))
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9"))) (setq r (strcat r c)))
    (setq i (1+ i)))
  r)

(defun sd:lic-raw (/ g comp vol fso drv)
  (setq g (vl-catch-all-apply 'vl-registry-read (list "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography" "MachineGuid")))
  (if (and (= (type g) 'STR) (/= g ""))
    (strcat "G:" g)
    (progn
      (setq comp (cond ((getenv "COMPUTERNAME")) ("")))
      (setq vol (vl-catch-all-apply
                  '(lambda ()
                     (setq fso (vlax-create-object "Scripting.FileSystemObject")
                           drv (vlax-invoke-method fso 'GetDrive "C:"))
                     (itoa (vlax-get-property drv 'SerialNumber)))
                  nil))
      (strcat "C:" comp "|V:" (if (= (type vol) 'STR) vol "")))))

;; Luu y: OR cua AutoLISP chi tra T / nil, khong tra gia tri -> dung COND de tra chuoi
(defun sd:lic-mid ()
  (cond (*SD:LICMID*)
        (t (setq *SD:LICMID* (sd:lic-mid-of (sd:lic-raw))))))

(defun sd:lic-expect () (sd:lic-code (strcat (sd:lic-mid) "|" *SD:LICSECRET*)))

(defun sd:lic-ok (/ st)
  (or *SD:LICOK*
      (progn
        (setq st (vl-catch-all-apply 'vl-registry-read (list *SD:LICREG* "License")))
        (if (and (= (type st) 'STR) (= (sd:lic-norm st) (sd:lic-norm (sd:lic-expect))))
          (setq *SD:LICOK* t)))))


;; --- Dung thu: so lan chay lenh khoa truoc khi kich hoat, luu 2 cho (registry + file) kem ma kiem tra gan voi may
(defun sd:lic-ucheck (n) (sd:lic-code (strcat "U|" (itoa n) "|" (sd:lic-mid) "|" *SD:LICSECRET*)))
(defun sd:lic-uparse (v / p n)
  ;; "n:ma" -> n neu hop le, nil neu sai / bi sua
  (if (and (= (type v) 'STR) (setq p (vl-string-search ":" v)))
    (progn (setq n (atoi (substr v 1 p)))
           (if (and (>= n 0) (= (substr v (+ p 2)) (sd:lic-ucheck n))) n))))
(defun sd:lic-ufile () (strcat (cond ((getenv "APPDATA")) ((getenv "TEMP")) ("C:")) "\\SDOpLat.dat"))
(defun sd:lic-uread (/ rv fv f a b)
  (setq rv (vl-catch-all-apply 'vl-registry-read (list *SD:LICREG* "Uses")))
  (if (vl-catch-all-error-p rv) (setq rv nil))
  (if (and (findfile (sd:lic-ufile)) (setq f (open (sd:lic-ufile) "r")))
    (progn (setq fv (read-line f)) (close f)))
  ;; co du lieu nhung khong hop le (bi sua) -> coi nhu het luot
  (setq a (if rv (sd:lic-uparse rv)) b (if fv (sd:lic-uparse fv)))
  (cond ((or (and rv (null a)) (and fv (null b))) *SD:LICTRIAL*)
        (t (max (cond (a) (0)) (cond (b) (0))))))
(defun sd:lic-uwrite (n / v f)
  (setq v (strcat (itoa n) ":" (sd:lic-ucheck n)))
  (vl-catch-all-apply 'vl-registry-write (list *SD:LICREG* "Uses" v))
  (if (setq f (vl-catch-all-apply 'open (list (sd:lic-ufile) "w")))
    (if (not (vl-catch-all-error-p f)) (progn (write-line v f) (close f)))))

(defun sd:lic-run (f / n)
  (cond
    ((sd:lic-ok) (apply f nil))
    ((< (setq n (sd:lic-uread)) *SD:LICTRIAL*)
     (sd:lic-uwrite (1+ n))
     (princ (strcat "\n[SD] Ban dung thu: con " (itoa (- *SD:LICTRIAL* n 1)) " / " (itoa *SD:LICTRIAL*)
                    " lan chay lenh. Go SDKICHHOAT de kich hoat."))
     (apply f nil))
    (t
     (princ (strcat "\n[SD] Het " (itoa *SD:LICTRIAL*) " lan dung thu. Go SDKICHHOAT, gui Ma may cho nha cung cap de nhan ma kich hoat."))
     (princ (strcat "\n     Ma may cua ban: " (sd:lic-mid)))
     (princ))))

(defun c:SDKICHHOAT (/ code)
  (princ (strcat "\n[SD] Ma may: " (sd:lic-mid)))
  (cond
    ((sd:lic-ok) (princ "\n[SD] Da kich hoat tren may nay."))
    (t
     (princ (strcat "\n[SD] Chua kich hoat (dung thu: da dung " (itoa (sd:lic-uread)) " / " (itoa *SD:LICTRIAL*) " lan). Gui Ma may o tren cho nha cung cap de nhan Ma kich hoat."))
     (setq code (getstring T "\nNhap Ma kich hoat <Enter = de sau>: "))
     (cond
       ((= (sd:lic-norm code) "") (princ "\n[SD] Chua nhap ma."))
       ((= (sd:lic-norm code) (sd:lic-norm (sd:lic-expect)))
        (vl-registry-write *SD:LICREG* "License" (sd:lic-expect))
        (vl-registry-write *SD:LICREG* "MachineId" (sd:lic-mid))
        (setq *SD:LICOK* t)
        (princ "\n[SD] Kich hoat thanh cong. Cam on ban da su dung phan mem."))
       (t (princ "\n[SD] Ma kich hoat khong dung cho may nay (kiem tra lai ma, hoac ma cap cho may khac)")))))
  (princ))

;; Kiem tra thuat toan: (sd:lic-selftest) phai in OK
(defun sd:lic-selftest ()
  (if (and (= (sd:lic-mid-of "G:TEST-MACHINE") "@@VEC_MID@@")
           (= (sd:lic-code "@@VEC_MID@@|TEST") "@@VEC_CODE@@"))
    (princ "\n[SD] Kiem tra ma kich hoat: OK")
    (princ "\n[SD] Kiem tra ma kich hoat: SAI - lien he nha cung cap"))
  (princ))
