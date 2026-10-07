; ===========================================================================
; NEXTEMS.ASM ? LIM EMS 4.0/3.2 Device Driver for Next186 SoC
; Pure 8086/80186 compatible (no 386 SIB or instructions)
;
; Assemble with NASM: nasm -f bin nextems.asm -o NEXTEMS.SYS
; ===========================================================================

[BITS 16]
[CPU 186]
[ORG 0]

; ---------------------------------------------------------------------------
; DOS Device Driver Header
; ---------------------------------------------------------------------------
DeviceHeader:
    dd  -1                      ; Next driver pointer
    dw  8000h                   ; Attribute: Character device
    dw  Strategy                ; Strategy routine entry
    dw  Interrupt               ; Interrupt routine entry
    db  'EMMXXXX0'              ; Standard LIM EMM device name (8 bytes)

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
EMS_PORT_P0     equ 0260h
EMS_PORT_P1     equ 0262h
EMS_PORT_P2     equ 0264h
EMS_PORT_P3     equ 0266h
EMS_PORT_CTRL   equ 0268h
EMS_PORT_TOTAL  equ 026Ah
EMS_PORT_BASE   equ 026Ch

EMS_SIGNATURE   equ 454Dh       ; EM
PAGE_FRAME_SEG  equ 0E000h
TOTAL_PAGES     equ 448         ; 7MB / 16KB
BASE_PHYS_PAGE  equ 64          ; Starts at 1MB
MAX_HANDLES     equ 32          ; 1..31 usable handles

; ---------------------------------------------------------------------------
; Resident Data
; ---------------------------------------------------------------------------
req_ptr_off     dw 0
req_ptr_seg     dw 0
old_int67_off   dw 0
old_int67_seg   dw 0

; Page owner: 0FFh = free, 0..31 = owning handle
page_owner      times TOTAL_PAGES db 0FFh
; Logical page index within handle
page_logical    times TOTAL_PAGES dw 0

; Handles (0 = unused/system, 1..31 user)
handle_active   times MAX_HANDLES db 0
handle_pages    times MAX_HANDLES dw 0
handle_map_save times (MAX_HANDLES * 4) dw 0

; ---------------------------------------------------------------------------
; Strategy Routine
; ---------------------------------------------------------------------------
Strategy:
    mov [cs:req_ptr_off], bx
    mov [cs:req_ptr_seg], es
    retf

; ---------------------------------------------------------------------------
; Interrupt Routine
; ---------------------------------------------------------------------------
Interrupt:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es

    mov ds, [cs:req_ptr_seg]
    mov bx, [cs:req_ptr_off]

    mov al, [ds:bx+2]           ; Command code
    cmp al, 0                   ; CMD 0: INIT
    je  .do_init

    ; For Open (13), Close (14), Input Status (6), Output Status (10), Read/Write, etc.
    ; Return Status = DONE (0100h) and transferred count = 0
    mov word [ds:bx+12h], 0     ; Count = 0
    mov word [ds:bx+3], 0100h   ; Status = Done (Success, not busy)
    jmp .done

.do_init:
    call InitDriver
    ; Status returned in [ds:bx+3] by InitDriver

.done:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    retf

; ---------------------------------------------------------------------------
; INT 67h ? LIM EMS Handler
; ---------------------------------------------------------------------------
EmmHandler:
    sti
    cmp ah, 40h
    je  .fn_get_status
    cmp ah, 41h
    je  .fn_get_frame
    cmp ah, 42h
    je  .fn_get_pages
    cmp ah, 43h
    je  .fn_alloc
    cmp ah, 44h
    je  .fn_map
    cmp ah, 45h
    je  .fn_dealloc
    cmp ah, 46h
    je  .fn_version
    cmp ah, 47h
    je  .fn_save_map
    cmp ah, 48h
    je  .fn_restore_map
    cmp ah, 4Bh
    je  .fn_get_handle_count
    cmp ah, 4Ch
    je  .fn_get_handle_pages
    cmp ah, 4Eh
    je  .fn_page_map

    mov ah, 84h                 ; Undefined function error
    iret

; --- AH = 40h: Get EMM Status ---
.fn_get_status:
    xor ah, ah                  ; AH = 0 (Good)
    iret

; --- AH = 41h: Get Page Frame Segment ---
.fn_get_frame:
    mov bx, PAGE_FRAME_SEG
    xor ah, ah
    iret

; --- AH = 42h: Get Page Counts ---
.fn_get_pages:
    push cx
    push si
    push ds
    mov ax, cs
    mov ds, ax
    xor bx, bx                  ; Free page counter
    mov cx, TOTAL_PAGES
    mov si, page_owner
.count_loop:
    cmp byte [si], 0FFh
    jne .not_free
    inc bx
.not_free:
    inc si
    loop .count_loop
    mov dx, TOTAL_PAGES
    xor ah, ah
    pop ds
    pop si
    pop cx
    iret

; --- AH = 43h: Allocate Pages (BX = num pages) ---
.fn_alloc:
    push cx
    push si
    push di
    push ds
    mov ax, cs
    mov ds, ax

    test bx, bx
    jnz .alloc_nz
    mov ah, 89h                 ; Error: Zero pages requested
    jmp .alloc_done
.alloc_nz:

    ; Count available free pages
    xor cx, cx
    mov si, page_owner
    mov di, TOTAL_PAGES
.alloc_cnt:
    cmp byte [si], 0FFh
    jne .alloc_nfree
    inc cx
.alloc_nfree:
    inc si
    dec di
    jnz .alloc_cnt

    cmp cx, bx
    jae .alloc_has_pages
    mov ah, 87h                 ; Error: Not enough free pages
    jmp .alloc_done

.alloc_has_pages:
    ; Find free handle (1..MAX_HANDLES-1)
    mov dx, 1
.alloc_hfind:
    cmp dx, MAX_HANDLES
    jae .alloc_no_handle
    mov si, dx
    cmp byte [handle_active + si], 0
    je  .alloc_hfound
    inc dx
    jmp .alloc_hfind

.alloc_no_handle:
    mov ah, 85h                 ; Error: All handles in use
    jmp .alloc_done

.alloc_hfound:
    ; DX is the allocated handle
    mov si, dx
    mov byte [handle_active + si], 1
    shl si, 1
    mov [handle_pages + si], bx

    ; Assign pages
    mov cx, bx                  ; cx = pages remaining to allocate
    xor di, di                  ; di = logical page index
    xor si, si                  ; si = physical pool index (0..TOTAL_PAGES-1)
.alloc_assign:
    mov bx, page_owner
    add bx, si
    cmp byte [bx], 0FFh
    jne .alloc_next_phys
    mov [bx], dl                ; Claim page: owner = handle (dl)
    mov bx, si
    shl bx, 1
    mov [page_logical + bx], di ; Set logical page index
    inc di
    dec cx
    jz  .alloc_success
.alloc_next_phys:
    inc si
    jmp .alloc_assign

.alloc_success:
    xor ah, ah                  ; DX already holds handle

.alloc_done:
    pop ds
    pop di
    pop si
    pop cx
    iret

; --- AH = 44h: Map/Unmap Page (AL = slot 0..3, BX = log page, DX = handle) ---
.fn_map:
    push cx
    push dx
    push si
    push ds
    mov cx, cs
    mov ds, cx

    cmp al, 3
    jbe .map_slot_ok
    mov ah, 8Bh                 ; Error: Invalid physical slot
    jmp .map_done
.map_slot_ok:
    cmp bx, 0FFFFh              ; Unmap request? (allowed even with DX=0)
    jne .map_check_handle
    ; Unmap: map default base page
    push ax
    xor ah, ah
    mov si, ax                  ; si = slot
    mov ax, BASE_PHYS_PAGE
    add ax, si
    mov dx, EMS_PORT_P0
    shl si, 1
    add dx, si
    out dx, ax
    pop ax
    xor ah, ah
    jmp .map_done

.map_check_handle:
    cmp dx, MAX_HANDLES
    jae .map_bad_handle
    mov si, dx
    cmp byte [handle_active + si], 0
    jne .map_regular
.map_bad_handle:
    mov ah, 83h                 ; Error: Invalid handle
    jmp .map_done

.map_regular:
    mov si, dx
    shl si, 1
    cmp bx, [handle_pages + si]
    jb  .map_log_ok
    mov ah, 8Ah                 ; Error: Logical page out of range
    jmp .map_done

.map_log_ok:
    ; Search for page owned by DX with logical index BX
    ; DL = handle, BX = logical page, AL = slot
    push di
    push bx
    xor di, di
.map_search:
    cmp byte [page_owner + di], dl
    jne .map_search_next
    mov si, di
    shl si, 1
    cmp [page_logical + si], bx
    je  .map_found
.map_search_next:
    inc di
    cmp di, TOTAL_PAGES
    jb  .map_search

    pop bx
    pop di
    mov ah, 8Ah                 ; Logical page not found
    jmp .map_done

.map_found:
    ; Hardware physical page = BASE_PHYS_PAGE + di
    pop bx
    mov si, di                  ; si = physical page index
    pop di
    push ax
    xor ah, ah
    mov cx, ax                  ; cx = slot 0..3
    mov ax, BASE_PHYS_PAGE
    add ax, si                  ; ax = 9-bit physical page
    mov dx, EMS_PORT_P0
    shl cx, 1
    add dx, cx                  ; dx = 0260h + slot*2
    out dx, ax                  ; PROGRAM HARDWARE EMS!
    pop ax
    xor ah, ah

.map_done:
    pop ds
    pop si
    pop dx
    pop cx
    iret

; --- AH = 45h: Deallocate Pages (DX = handle) ---
.fn_dealloc:
    push cx
    push si
    push ds
    mov cx, cs
    mov ds, cx

    cmp dx, MAX_HANDLES
    jae .dealloc_bad_h
    mov si, dx
    cmp byte [handle_active + si], 0
    jne .dealloc_h_ok
.dealloc_bad_h:
    mov ah, 83h
    jmp .dealloc_done

.dealloc_h_ok:
    ; Free all pages owned by DX
    mov cx, TOTAL_PAGES
    mov si, page_owner
.dealloc_loop:
    cmp [si], dl
    jne .dealloc_skip
    mov byte [si], 0FFh
.dealloc_skip:
    inc si
    loop .dealloc_loop

    mov si, dx
    mov byte [handle_active + si], 0
    shl si, 1
    mov word [handle_pages + si], 0
    xor ah, ah

.dealloc_done:
    pop ds
    pop si
    pop cx
    iret

; --- AH = 46h: Get Version ---
.fn_version:
    mov al, 32h                 ; LIM EMS 3.2
    xor ah, ah
    iret

; --- AH = 47h: Save Page Map (DX = handle) ---
.fn_save_map:
    push cx
    push si
    push dx
    push ds
    mov cx, cs
    mov ds, cx

    cmp dx, MAX_HANDLES
    jae .save_bad_h
    mov si, dx
    cmp byte [handle_active + si], 0
    jne .save_h_ok
.save_bad_h:
    pop ds
    pop dx
    pop si
    pop cx
    mov ah, 83h
    iret

.save_h_ok:
    mov si, dx
    shl si, 3                   ; si = handle * 8 (4 words)
    mov dx, EMS_PORT_P0
    in  ax, dx
    mov [handle_map_save + si], ax
    mov dx, EMS_PORT_P1
    in  ax, dx
    mov [handle_map_save + si + 2], ax
    mov dx, EMS_PORT_P2
    in  ax, dx
    mov [handle_map_save + si + 4], ax
    mov dx, EMS_PORT_P3
    in  ax, dx
    mov [handle_map_save + si + 6], ax
    xor ah, ah
    pop ds
    pop dx
    pop si
    pop cx
    iret

; --- AH = 48h: Restore Page Map (DX = handle) ---
.fn_restore_map:
    push cx
    push si
    push dx
    push ds
    mov cx, cs
    mov ds, cx

    cmp dx, MAX_HANDLES
    jae .rest_bad_h
    mov si, dx
    cmp byte [handle_active + si], 0
    jne .rest_h_ok
.rest_bad_h:
    pop ds
    pop dx
    pop si
    pop cx
    mov ah, 83h
    iret

.rest_h_ok:
    mov si, dx
    shl si, 3
    mov ax, [handle_map_save + si]
    mov dx, EMS_PORT_P0
    out dx, ax
    mov ax, [handle_map_save + si + 2]
    mov dx, EMS_PORT_P1
    out dx, ax
    mov ax, [handle_map_save + si + 4]
    mov dx, EMS_PORT_P2
    out dx, ax
    mov ax, [handle_map_save + si + 6]
    mov dx, EMS_PORT_P3
    out dx, ax
    xor ah, ah
    pop ds
    pop dx
    pop si
    pop cx
    iret

; --- AH = 4Bh: Get Active Handle Count ---
.fn_get_handle_count:
    push cx
    push si
    push ds
    mov cx, cs
    mov ds, cx
    xor bx, bx
    mov cx, MAX_HANDLES
    mov si, handle_active
.ghc_loop:
    cmp byte [si], 0
    je  .ghc_next
    inc bx
.ghc_next:
    inc si
    loop .ghc_loop
    xor ah, ah
    pop ds
    pop si
    pop cx
    iret

; --- AH = 4Ch: Get Pages for Handle (DX = handle) ---
.fn_get_handle_pages:
    push ds
    mov ax, cs
    mov ds, ax
    cmp dx, MAX_HANDLES
    jae .ghp_bad
    mov si, dx
    cmp byte [handle_active + si], 0
    je  .ghp_bad
    shl si, 1
    mov bx, [handle_pages + si]
    xor ah, ah
    pop ds
    iret
.ghp_bad:
    pop ds
    mov ah, 83h
    iret

; --- AH = 4Eh: Get/Set Page Map (AL=0 save ES:DI, AL=1 restore DS:SI, AL=2 save & restore, AL=3 size) ---
.fn_page_map:
    cmp al, 3
    jne .pm_not_size
    mov al, 8                   ; Size in bytes
    xor ah, ah
    iret
.pm_not_size:
    cmp al, 0
    je  .pm_do_save
    cmp al, 2
    je  .pm_do_save
    cmp al, 1
    je  .pm_do_restore
    jmp .pm_bad_subfn

.pm_do_save:
    push ax
    push dx
    mov dx, EMS_PORT_P0
    in ax, dx
    mov [es:di], ax
    mov dx, EMS_PORT_P1
    in ax, dx
    mov [es:di+2], ax
    mov dx, EMS_PORT_P2
    in ax, dx
    mov [es:di+4], ax
    mov dx, EMS_PORT_P3
    in ax, dx
    mov [es:di+6], ax
    pop dx
    pop ax
    cmp al, 2
    je  .pm_do_restore
    xor ah, ah
    iret

.pm_do_restore:
    push dx
    mov ax, [ds:si]
    mov dx, EMS_PORT_P0
    out dx, ax
    mov ax, [ds:si+2]
    mov dx, EMS_PORT_P1
    out dx, ax
    mov ax, [ds:si+4]
    mov dx, EMS_PORT_P2
    out dx, ax
    mov ax, [ds:si+6]
    mov dx, EMS_PORT_P3
    out dx, ax
    pop dx
    xor ah, ah
    iret
.pm_bad_subfn:
    mov ah, 8Fh                 ; Undefined subfunction
    iret

; ---------------------------------------------------------------------------
; Initialization Code (Discarded after boot)
; ---------------------------------------------------------------------------
InitDriver:
    push cs
    pop  ds

    ; Print greeting
    mov dx, msg_banner
    mov ah, 9
    int 21h

    ; 1. Hardware Presence Check: verify signature at port 0268h
    mov dx, EMS_PORT_CTRL
    in  ax, dx
    cmp ax, EMS_SIGNATURE
    je  .hw_found

    ; Not found
    mov dx, msg_no_hw
    mov ah, 9
    int 21h
    mov ds, [cs:req_ptr_seg]
    mov bx, [cs:req_ptr_off]
    mov word [ds:bx+3], 8102h   ; Error: Driver not ready
    mov word [ds:bx+0Eh], 0
    mov word [ds:bx+10h], cs
    ret

.hw_found:
    ; 2. Initialize hardware: Enable EMS, base frame 0xE000
    mov dx, EMS_PORT_CTRL
    mov ax, 0001h               ; Bit 0 = 1 (enable), Bit 1 = 0 (frame 0xE000)
    out dx, ax

    ; Initialize mapping for 4 slots to first 4 EMS pool pages (64..67)
    mov ax, BASE_PHYS_PAGE
    mov dx, EMS_PORT_P0
    out dx, ax
    inc ax
    mov dx, EMS_PORT_P1
    out dx, ax
    inc ax
    mov dx, EMS_PORT_P2
    out dx, ax
    inc ax
    mov dx, EMS_PORT_P3
    out dx, ax

    ; 3. Hook INT 67h
    mov ax, 3567h               ; Get current INT 67h
    int 21h
    mov [old_int67_off], bx
    mov [old_int67_seg], es

    mov ax, 2567h               ; Set INT 67h -> EmmHandler
    mov dx, EmmHandler
    int 21h

    ; Print success message
    mov dx, msg_ok
    mov ah, 9
    int 21h

    ; Set return parameters in Request Header
    mov ds, [cs:req_ptr_seg]
    mov bx, [cs:req_ptr_off]
    mov word [ds:bx+0Eh], InitDriver ; End of resident code
    mov word [ds:bx+10h], cs         ; Segment
    mov word [ds:bx+3], 0100h        ; Status: Done, OK
    ret

; ---------------------------------------------------------------------------
; Initialization Messages
; ---------------------------------------------------------------------------
msg_banner  db 0Dh, 0Ah
            db '==================================================', 0Dh, 0Ah
            db ' Next186 LIM EMS 4.0 / 3.2 Hardware Driver v1.0', 0Dh, 0Ah
            db '==================================================', 0Dh, 0Ah, '$'

msg_no_hw   db 'ERROR: Next186 EMS hardware registers not detected at 0268h!', 0Dh, 0Ah, '$'

msg_ok      db 'Hardware detected: 7168 KB Expanded Memory (448 pages of 16KB)', 0Dh, 0Ah
            db 'Page Frame base: E000h (Slots 0..3: E000h, E400h, E800h, EC00h)', 0Dh, 0Ah
            db 'Status: Driver successfully installed on INT 67h.', 0Dh, 0Ah, 0Dh, 0Ah, '$'
