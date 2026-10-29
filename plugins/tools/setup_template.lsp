;;; ==========================================================================
;;;  CAI DAT TU DONG - Op Lat Tools v@@VER@@
;;;  Cach dung: mo AutoCAD, KEO THA file nay vao cua so AutoCAD (hoac go APPLOAD, chon file nay, bam Load).
;;;  File tu giai ma toan bo goi vao
;;;    %APPDATA%\Autodesk\ApplicationPlugins\SDOpLat.bundle\Contents
;;;  roi cai menu + toolbar. Cac lan mo AutoCAD sau plugin tu nap (co the can khoi dong lai AutoCAD 1 lan).
;;;  Khong can quyen quan tri. Go cai dat: xoa thu muc SDOpLat.bundle va go SDMENUXOA.
;;; ==========================================================================
(vl-load-com)
(setq *SDSU:VER* "@@VER@@" *SDSU:OK* 0 *SDSU:BAD* nil *SDSU:ERR1* nil)

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

;; Giai ma base64 -> file nhi phan (MSXML + ADODB.Stream, co san tren Windows)
(defun sdsu:fail (msg)
  (setq *SDSU:FAIL* t)
  (if (not *SDSU:ERR1*) (progn (setq *SDSU:ERR1* t) (princ (strcat "\n[SETUP] Loi ghi file: " msg))))
  (princ))

;; Moi file: (sdsu:f ten kich-thuoc) mo luong ghi, nhieu (sdsu:c "doan base64 ngan"), (sdsu:e) dong va kiem tra kich thuoc.
;; Doan ngan (400 ky tu, nho hon chuoi dai nhat da biet nap duoc trong plugin: 430) vi AutoLISP gioi han do dai chuoi trong file; moi doan tu giai ma roi ghi noi tiep.
(defun sdsu:f (rel size / r)
  (setq *SDSU:REL* rel *SDSU:SIZE* size *SDSU:FAIL* nil *SDSU:PATH* (strcat (sdsu:dir) "\\" rel)
        *SDSU:XML* nil *SDSU:EL* nil *SDSU:ST* nil)
  (if (not *SDSU:ABORT*)
    (progn
      (setq r (vl-catch-all-apply
                '(lambda ()
                   (sdsu:mkdirs (vl-filename-directory *SDSU:PATH*))
                   (setq *SDSU:XML* (vlax-create-object "MSXML2.DOMDocument.6.0"))
                   (setq *SDSU:EL* (vlax-invoke-method *SDSU:XML* 'createElement "b64"))
                   (vlax-put-property *SDSU:EL* 'dataType "bin.base64")
                   (setq *SDSU:ST* (vlax-create-object "ADODB.Stream"))
                   (vlax-put-property *SDSU:ST* 'Type 1)
                   (vlax-invoke-method *SDSU:ST* 'Open))
                nil))
      (if (vl-catch-all-error-p r) (sdsu:fail (vl-catch-all-error-message r)))))
  (princ))

(defun sdsu:c (b64 / r)
  (if (and (not *SDSU:ABORT*) (not *SDSU:FAIL*))
    (progn
      (setq r (vl-catch-all-apply
                '(lambda ()
                   (vlax-put-property *SDSU:EL* 'text b64)
                   (vlax-invoke-method *SDSU:ST* 'Write (vlax-get-property *SDSU:EL* 'nodeTypedValue)))
                nil))
      (if (vl-catch-all-error-p r) (sdsu:fail (vl-catch-all-error-message r)))))
  (princ))

(defun sdsu:e ( / r)
  (if (not *SDSU:ABORT*)
    (progn
      (if (and *SDSU:ST* (not *SDSU:FAIL*))
        (progn
          (setq r (vl-catch-all-apply '(lambda () (vlax-invoke-method *SDSU:ST* 'SaveToFile *SDSU:PATH* 2)) nil))
          (if (vl-catch-all-error-p r) (sdsu:fail (vl-catch-all-error-message r)))))
      (if *SDSU:ST* (progn (vl-catch-all-apply '(lambda () (vlax-invoke-method *SDSU:ST* 'Close)) nil)
                           (vl-catch-all-apply 'vlax-release-object (list *SDSU:ST*))))
      (if *SDSU:XML* (vl-catch-all-apply 'vlax-release-object (list *SDSU:XML*)))
      (if (and (not *SDSU:FAIL*) (findfile *SDSU:PATH*) (= (vl-file-size *SDSU:PATH*) *SDSU:SIZE*))
        (setq *SDSU:OK* (1+ *SDSU:OK*))
        (setq *SDSU:BAD* (cons *SDSU:REL* *SDSU:BAD*)))))
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
