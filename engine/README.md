# Engine Vietfox

Vietfox là addon Fcitx5 riêng, được dựng từ mã nguồn engine Ngó Sen. Giao diện cài đặt,
launcher, tên addon và input method do Vietfox quản lý; source GUI Ngó Sen không được đóng gói.
Phần lõi xử lý tiếng Việt được giữ để tương thích hành vi gõ.

## Tương thích

- Addon Fcitx5: `vietfox`, thư viện `libvietfox.so`.
- Addon di trú cấu hình: `vietfoxmigrate`, thư viện `libvietfoxmigrate.so`.
- Tên hiển thị và input method: `Vietfox`.
- Cài đặt cũ trong `~/.config/fcitx5/conf/ngosen.conf`, gõ tắt, quy tắc ứng dụng và từ điển
  Ngó Sen được giữ nguyên để Vietfox dùng tiếp.
- Source upstream: https://github.com/ngosen/ngosen, commit `7cb39e4`.
- Lõi ghép dấu Go: submodule `bamboo/bamboo-core` tại commit
  `e896341c568584d9cd8db0836d7ecb8d6ff79d1b`.
- Giấy phép: GPL-3.0-or-later; giấy phép phụ nằm trong `source/LICENSES/`.

Thư mục `source/` chỉ chứa engine và dữ liệu runtime cần build. Giao diện Settings Ngó Sen,
desktop entry, metadata và GNOME extension upstream không được build từ đây.

## Build trên Ubuntu

Máy cần CMake, trình biên dịch C/C++, Go, gettext, Fcitx5 headers, ECM, librsvg và các gói
phát triển của Fcitx5. Từ gốc repo:

```sh
cmake -S engine/source -B build/engine -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib
cmake --build build/engine --parallel
DESTDIR=/tmp/vietfox-engine-stage cmake --install build/engine
```

Build tạo `libvietfox.so`, `libvietfoxmigrate.so`, addon descriptor và input method `vietfox`.
Script `./engine/build-ubuntu.sh` build và cập nhật artifact Vietfox cho Ubuntu 26.04 amd64.
Không chạy lệnh install vào `/usr` trong bước build. Binary theo Ubuntu/kiến trúc nằm trong
`variants/ubuntu/<codename>/<architecture>/`.

## Build trên Arch Linux

Đã build và chạy thử trên Arch Linux với Fcitx5 5.1.23, CMake 4.4 và GNOME Shell 51 (Wayland).
Máy cần `base-devel` để có trình biên dịch, cùng các gói:

```sh
sudo pacman -S --needed base-devel cmake extra-cmake-modules fcitx5 gettext librsvg go
```

Từ gốc repo:

```sh
cmake -S engine/source -B build/engine -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=/usr/lib
cmake --build build/engine --parallel
sudo cmake --install build/engine
```

Arch không tách gói header như Ubuntu: gói `fcitx5` đã có `Fcitx5Core`, `Fcitx5ModuleEmoji` và
các module addon cần thiết, nên không cần gói `-dev` riêng. `CMAKE_INSTALL_LIBDIR=/usr/lib` là
bắt buộc vì Fcitx5 trên Arch nạp addon từ `/usr/lib/fcitx5`. Lệnh install chép:

- `/usr/lib/fcitx5/libvietfox.so` và `libvietfoxmigrate.so`
- `/usr/share/fcitx5/addon/vietfox.conf` và `vietfoxmigrate.conf`
- `/usr/share/fcitx5/inputmethod/vietfox.conf`
- `/usr/share/icons/hicolor/scalable/apps/fcitx-vietfox*.svg`
- `/usr/share/locale/vi/LC_MESSAGES/fcitx5-vietfox.mo`

Sau khi cài, đăng xuất rồi đăng nhập lại để Fcitx5 nạp addon, sau đó thêm bộ gõ trong
`fcitx5-configtool`. Chọn **Vietfox** ở danh sách input method và giữ **keyboard-us** ở ô đầu
tiên của nhóm.

`./engine/build-ubuntu.sh` chỉ chạy trên Ubuntu Resolute amd64 vì nó cập nhật binary trong
`variants/ubuntu/`; trên Arch hãy dùng các lệnh CMake ở trên.

Tên `ngosen` còn trong namespace nội bộ và các đường dẫn cấu hình tương thích. Không đổi các
đường dẫn đó nếu chưa có bước chuyển cấu hình và kiểm tra dữ liệu cũ.
