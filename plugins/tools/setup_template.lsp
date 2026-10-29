;;; ==========================================================================
;;;  CAI DAT TU DONG - Op Lat Tools v@@VER@@
;;;  Cach dung: mo AutoCAD, KEO THA file nay vao cua so AutoCAD (hoac go APPLOAD, chon file nay, bam Load).
;;;  File tu giai ma toan bo goi vao
;;;    %APPDATA%\Autodesk\ApplicationPlugins\SDOpLat.bundle\Contents
;;;  roi cai menu + toolbar. Cac lan mo AutoCAD sau plugin tu nap (co the can khoi dong lai AutoCAD 1 lan).
;;;  Khong can quyen quan tri. Go cai dat: xoa thu muc SDOpLat.bundle va go SDMENUXOA.
;;; ==========================================================================
(vl-load-com)
(setq *SDSU:VER* "@@VER@@" *SDSU:OK* 0 *SDSU:BAD* nil)

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
(defun sdsu:put1 (rel size chunks / path xml el st bytes err b64)
  (setq path (strcat (sdsu:dir) "\\" rel)
        err (vl-catch-all-apply
              '(lambda ()
                 (sdsu:mkdirs (vl-filename-directory path))
                 (setq xml (vlax-create-object "MSXML2.DOMDocument.6.0"))
                 (setq el (vlax-invoke-method xml 'createElement "b64"))
                 (vlax-put-property el 'dataType "bin.base64")
                 (setq b64 "")
                 (foreach c chunks (setq b64 (strcat b64 c)))
                 (vlax-put-property el 'text b64)
                 (setq bytes (vlax-get-property el 'nodeTypedValue))
                 (setq st (vlax-create-object "ADODB.Stream"))
                 (vlax-put-property st 'Type 1)
                 (vlax-invoke-method st 'Open)
                 (vlax-invoke-method st 'Write bytes)
                 (vlax-invoke-method st 'SaveToFile path 2)
                 (vlax-invoke-method st 'Close))
              nil))
  (if st (vl-catch-all-apply 'vlax-release-object (list st)))
  (if xml (vl-catch-all-apply 'vlax-release-object (list xml)))
  (if (and (not (vl-catch-all-error-p err)) (findfile path) (= (vl-file-size path) size))
    (setq *SDSU:OK* (1+ *SDSU:OK*))
    (setq *SDSU:BAD* (cons rel *SDSU:BAD*)))
  (princ))

(defun sdsu:put (rel size chunks)
  (if (not *SDSU:ABORT*) (sdsu:put1 rel size chunks))
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
