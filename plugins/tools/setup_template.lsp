;;; ==========================================================================
;;;  CAI DAT TU DONG - Op Lat Tools v@@VER@@
;;;  Cach dung: mo AutoCAD, KEO THA file nay vao cua so AutoCAD (hoac go APPLOAD, chon file nay, bam Load).
;;;  File tu giai ma toan bo goi vao
;;;    %APPDATA%\Autodesk\ApplicationPlugins\SDOpLat.bundle\Contents
;;;  roi cai menu + toolbar. Cac lan mo AutoCAD sau plugin tu nap (co the can khoi dong lai AutoCAD 1 lan).
;;;  Khong can quyen quan tri. Go cai dat: xoa thu muc SDOpLat.bundle va go SDMENUXOA.
;;; ==========================================================================
(vl-load-com)
(setq *SDSU:VER* "@@VER@@" *SDSU:OK* 0 *SDSU:BAD* nil *SDSU:ERR1* nil *SDSU:SH* nil)

(defun sdsu:mkdirs (path / parts cur)
  ;; tao tung cap thu muc (vl-mkdir chi tao 1 cap)
  (setq parts (sdsu:split path "\\") cur (car parts))
  (foreach p (cdr parts)
    (setq cur (strcat cur "\\" p))
    (if (not (vl-file-directory-p cur)) (vl-mkdir cur)))
  (vl-file-directory-p path))

(defun sdsu:split (s sep / r i k)
  (setq r nil i 1 k 1)
  (while (<= i (strlen s))
    (if (= (substr s i 1) sep)
      (progn (setq r (cons (substr s k (- i k)) r) k (1+ i))))
    (setq i (1+ i)))
  (reverse (cons (substr s k) r)))

(defun sdsu:root () (strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\SDOpLat.bundle"))
(defun sdsu:dir () (strcat (sdsu:root) "\\Contents"))

;; Giai ma base64 -> file nhi phan (MSXML giai ma, AutoLISP write-char ghi byte)
(defun sdsu:fail (msg)
  (setq *SDSU:FAIL* t)
  (if (not *SDSU:ERR1*) (progn (setq *SDSU:ERR1* t) (princ (strcat "\n[SETUP] Loi ghi file: " msg))))
  (princ))

;; Moi file: (sdsu:f ten kich-thuoc) mo luong ghi, nhieu (sdsu:c "doan base64 ngan"), (sdsu:e) dong va kiem tra kich thuoc.
;; Doan ngan (400 ky tu, nho hon chuoi dai nhat da biet nap duoc trong plugin: 430) vi AutoLISP gioi han do dai chuoi trong file; moi doan tu giai ma roi ghi noi tiep.
(defun sdsu:sh ()
  (if (not *SDSU:SH*) (setq *SDSU:SH* (vl-catch-all-apply 'vlax-create-object (list "WScript.Shell"))))
  (if (vl-catch-all-error-p *SDSU:SH*) (setq *SDSU:SH* nil))
  *SDSU:SH*)

;; AutoLISP write-char doi byte (LF->CRLF, mat byte 0) nen KHONG dung duoc cho file nhi phan.
;; Cach lam: ghi base64 (chi ky tu ASCII) ra file tam .b64 bang write-line, roi nho Windows giai ma bang certutil -decode.
(defun sdsu:f (rel size / r)
  (setq *SDSU:REL* rel *SDSU:SIZE* size *SDSU:FAIL* nil *SDSU:PATH* (strcat (sdsu:dir) "\\" rel)
        *SDSU:TMP* (strcat (sdsu:dir) "\\" "sdoplat_tmp.b64") *SDSU:FH* nil *SDSU:STEP* "bat dau")
  (if (not *SDSU:ABORT*)
    (progn
      (setq *SDSU:STEP* "tao thu muc")
      (sdsu:mkdirs (vl-filename-directory *SDSU:PATH*))
      (setq r (vl-catch-all-apply
                '(lambda ()
                   (setq *SDSU:STEP* "mo file tam")
                   (if (findfile *SDSU:TMP*) (vl-file-delete *SDSU:TMP*))
                   (if (findfile *SDSU:PATH*) (vl-file-delete *SDSU:PATH*))
                   (setq *SDSU:FH* (open *SDSU:TMP* "w"))
                   (if (not *SDSU:FH*) (error "khong mo duoc file tam de ghi")))
                nil))
      (if (vl-catch-all-error-p r)
        (sdsu:fail (strcat "buoc [" *SDSU:STEP* "]: " (vl-catch-all-error-message r))))))
  (princ))

(defun sdsu:c (b64)
  (if (and (not *SDSU:ABORT*) (not *SDSU:FAIL*) *SDSU:FH*) (write-line b64 *SDSU:FH*))
  (princ))

(defun sdsu:e ( / r)
  (if (not *SDSU:ABORT*)
    (progn
      (if *SDSU:FH* (progn (close *SDSU:FH*) (setq *SDSU:FH* nil)))
      (if (not *SDSU:FAIL*)
        (progn
          (setq *SDSU:STEP* "certutil")
          (if (sdsu:sh)
            (progn
              (setq r (vl-catch-all-apply 'vlax-invoke-method
                        (list *SDSU:SH* 'Run
                              (strcat "cmd /c \"certutil -f -decode \"" *SDSU:TMP* "\" \"" *SDSU:PATH* "\" >nul 2>&1\"")
                              0 :vlax-true)))
              (if (vl-catch-all-error-p r) (sdsu:fail (strcat "buoc [" *SDSU:STEP* "]: " (vl-catch-all-error-message r)))))
            (sdsu:fail "khong tao duoc WScript.Shell (can de goi certutil)"))))
      (if (findfile *SDSU:TMP*) (vl-file-delete *SDSU:TMP*))
      (if (and (not *SDSU:FAIL*) (findfile *SDSU:PATH*) (= (vl-file-size *SDSU:PATH*) *SDSU:SIZE*))
        (setq *SDSU:OK* (1+ *SDSU:OK*))
        (progn
          (if (and (not *SDSU:FAIL*) (not *SDSU:ERR1*))
            (sdsu:fail (strcat "kich thuoc sau giai ma sai: " *SDSU:REL* " (can " (itoa *SDSU:SIZE*) ", co " (if (findfile *SDSU:PATH*) (itoa (vl-file-size *SDSU:PATH*)) "khong co file") ")")))
          (setq *SDSU:BAD* (cons *SDSU:REL* *SDSU:BAD*))))))
  (princ))

(defun sdsu:xml ( / f p)
  (setq p (strcat (sdsu:root) "\\PackageContents.xml") f (open p "w"))
  (if f
    (progn
      (foreach l '("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                   "<ApplicationPackage SchemaVersion=\"1.0\" ProductType=\"Application\" Name=\"SDOpLat\" AppVersion=\"@@VER@@\" Description=\"Op Lat Tools\" AppNameSpace=\"sdoplat.local\" Author=\"SDOpLat\">"
                   "  <CompanyDetails Name=\"SDOpLat\" />"
                   "  <Components Description=\"Op Lat Tools\">"
                   "    <RuntimeRequirements OS=\"Win32|Win64\" Platform=\"AutoCAD*\" SeriesMin=\"R18.0\" />"
                   "    <ComponentEntry AppName=\"SDOpLat\" Version=\"@@VER@@\" ModuleName=\"./Contents/@@MAIN@@\" AppDescription=\"Op Lat Tools\" LoadOnCommandInvocation=\"False\" LoadOnAutoCADStartup=\"True\" />"
                   "  </Components>"
                   "</ApplicationPackage>")
        (write-line l f))
      (close f) t)))

(defun sdsu:clean ( / b)
  ;; xoa ban menu da chuyen doi cua lan cai truoc de AutoCAD chuyen lai tu .mnu moi
  (foreach e '("cuix" "mns" "mnc" "mnr")
    (setq b (strcat (sdsu:dir) "\\SDOpLat." e))
    (if (findfile b) (vl-catch-all-apply 'vl-file-delete (list b)))))

(defun sdsu:begin ( / d)
  (princ "\n[SETUP] Op Lat Tools v@@VER@@: dang giai ma va cai dat (khoang vai chuc giay)...")
  ;; ban ShopDrawing cu dang nap trong phien nay (co the che ban moi sau khi mo lai AutoCAD)
  (setq *SDSU:OLDVER* (if (and (boundp '*SD:VER*) *SD:VER* (/= *SD:VER* "@@VER@@")) *SD:VER* nil))
  (if *SDSU:OLDVER*
    (princ (strcat "\n[SETUP] CANH BAO: dang nap ban ShopDrawing cu v" *SDSU:OLDVER* ". Sau khi cai xong, go bo ban cu khoi Support Path / Startup Suite / acaddoc.lsp / menu SHOPDRAWING, neu khong AutoCAD co the tiep tuc nap ban cu.")))
  (setq *SDSU:ABORT* nil)
  (cond
    ((not (and (boundp 'vlax-create-object) vlax-create-object))
     (setq *SDSU:ABORT* t)
     (princ "\n[SETUP] Ban AutoCAD nay khong ho tro COM (vi du AutoCAD LT) nen khong cai tu dong duoc."))
    ((not (sdsu:mkdirs (sdsu:dir)))
     (setq *SDSU:ABORT* t)
     (princ (strcat "\n[SETUP] Khong tao duoc thu muc " (sdsu:dir))))
    (t (sdsu:clean)))
  (princ))

(defun sdsu:end ()
  (if (not *SDSU:ABORT*) (progn (sdsu:xml) (sdsu:finish)))
  (princ))

(defun sdsu:finish ( / mn r)
  (if *SDSU:BAD*
    (princ (strcat "\n[SETUP] LOI: " (itoa (length *SDSU:BAD*)) " file chua ghi duoc: " (apply 'strcat (mapcar '(lambda (x) (strcat x "  ")) (reverse *SDSU:BAD*)))
                   "\n        Dong cac chuong trinh dang mo file, thu lai; neu van loi, bao nha cung cap."))
    (progn
      (princ (strcat "\n[SETUP] Da ghi " (itoa *SDSU:OK*) " file vao " (sdsu:dir)))
      ;; nap ngay va cai menu + toolbar
      (setq mn (strcat (sdsu:dir) "\\@@MAIN@@"))
      (if (findfile mn) (vl-catch-all-apply 'load (list mn)))
      (cond
        ((and (boundp 'sd:add-path) (boundp 'sd:mg-load) (findfile (strcat (sdsu:dir) "\\SDOpLat.mnu")))
         ;; them thu muc vao Support Path + Trusted Locations, nap menu va dua vao thanh menu
         (vl-catch-all-apply 'sd:add-path (list (sdsu:dir)))
         (setq r (vl-catch-all-apply 'sd:mg-load (list (strcat (sdsu:dir) "\\SDOpLat.mnu") "SDOPLAT")))
         (if (and r (not (vl-catch-all-error-p r)))
           (progn (vl-catch-all-apply 'sd:menu-bar (list "SDOPLAT"))
                  (princ "\n[SETUP] Da nap menu + toolbar SDOpLat."))
           (princ "\n[SETUP] Chua nap duoc menu: go SDMENU de nap lai.")))
        (t (princ "\n[SETUP] Chua nap duoc lenh: khoi dong lai AutoCAD roi go SDMENU.")))
      (princ "\n[SETUP] XONG. Khoi dong lai AutoCAD mot lan de plugin tu nap cho cac lan sau.")
      (princ "\n        Go SDPANEL de xem bang lenh, SDKICHHOAT de kich hoat. Tro ly hoi dap: mo TroLyOpLat.html trong thu muc cai dat.")))
  (princ))

(sdsu:begin)
@@FILES@@
(sdsu:end)
(princ)
