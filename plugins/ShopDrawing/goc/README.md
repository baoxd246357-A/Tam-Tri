# Bản gốc của các lệnh tích hợp

Giữ nguyên văn (có dấu, chưa chỉnh) để truy hồi khi cần:

| File gốc | Lệnh gốc | Tích hợp thành | Ghi chú |
|---|---|---|---|
| `DimGiaoDiem_v2.lsp` | `DGD` | `SDDIMGD` (lệnh tắt `DGD`) | thêm tùy chọn chữ dim cạnh đường dim |
| `DimPolyline_v2.lsp` | `DPK` | `SDDIMPOLY` (lệnh tắt `DPK`) | thêm tùy chọn chữ dim cạnh đường dim |

Mã tích hợp: `tools/modules/dgd.lsp` + `tools/modules/dpk.lsp` (dán nguyên vào `ShopDrawing.lsp`, đoạn "SDDIMGD (DGD) va SDDIMPOLY (DPK)").
Muốn dùng lại bản gốc độc lập: nạp thẳng file trong thư mục này.
