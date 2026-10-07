; ===========================================================================
; EMSTEST.ASM ? Standalone LIM EMS Diagnostic & Test Utility for DOS
;
; Assemble with NASM: nasm -f bin emstest.asm -o EMSTEST.COM
; ===========================================================================

[BITS 16]
[CPU 186]
[ORG 100h]

start:
    ; Print Title Banner
    mov dx, msg_title
    mov ah, 9
    int 21h

    ; Step 1: Detect EMM via INT 67h, AH=40h
    mov ah, 40h
    int 67h
    test ah, ah
    jz  .emm_present

    mov dx, msg_no_emm
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h

.emm_present:
    mov dx, msg_emm_found
    mov ah, 9
    int 21h

    ; Step 2: Get Page Frame (AH=41h)
    mov ah, 41h
    int 67h
    test ah, ah
    jz  .frame_ok

    mov dx, msg_err_frame
    mov ah, 9
    int 21h
    jmp .fail

.frame_ok:
    mov [page_frame_seg], bx
    mov ax, bx
    call PrintHex16
    mov dx, msg_frame_ok
    mov ah, 9
    int 21h

    ; Step 3: Get Page Counts (AH=42h)
    mov ah, 42h
    int 67h
    test ah, ah
    jz  .pages_ok

    mov dx, msg_err_pages
    mov ah, 9
    int 21h
    jmp .fail

.pages_ok:
    push dx                     ; Save total pages
    push bx                     ; Save free pages

    mov dx, msg_free_pfx
    mov ah, 9
    int 21h
    pop ax                      ; Free pages
    call PrintDec16
    mov dx, msg_total_pfx
    mov ah, 9
    int 21h
    pop ax                      ; Total pages
    call PrintDec16
    mov dx, msg_crlf
    mov ah, 9
    int 21h

    ; Step 4: Allocate 4 Pages (64 KB) (AH=43h, BX=4)
    mov dx, msg_allocating
    mov ah, 9
    int 21h

    mov ah, 43h
    mov bx, 4
    int 67h
    test ah, ah
    jz  .alloc_ok

    mov dx, msg_err_alloc
    mov ah, 9
    int 21h
    jmp .fail

.alloc_ok:
    mov [my_handle], dx
    mov dx, msg_alloc_ok
    mov ah, 9
    int 21h

    ; Step 5: Test Banking Data Integrity
    ; Map logical page 0 to physical slot 0 (AL=0, BX=0, DX=handle)
    mov dx, [my_handle]
    mov ax, 4400h
    xor bx, bx
    int 67h
    test ah, ah
    jnz .fail_map

    ; Fill slot 0 with Pattern A (0x55AA, 0x1234, ...)
    mov es, [page_frame_seg]
    xor di, di
    mov cx, 8192                ; 8192 words = 16384 bytes
    mov ax, 55AAh
.fill_p0:
    stosw
    add ax, 0001h
    loop .fill_p0

    ; Map logical page 1 to physical slot 0 (AL=0, BX=1, DX=handle)
    mov dx, [my_handle]
    mov ax, 4400h
    mov bx, 1
    int 67h
    test ah, ah
    jnz .fail_map

    ; Fill slot 0 with Pattern B (0xAA55, 0x9876, ...)
    xor di, di
    mov cx, 8192
    mov ax, 0AA55h
.fill_p1:
    stosw
    add ax, 0001h
    loop .fill_p1

    ; Verify Pattern B on logical page 1
    xor di, di
    mov cx, 8192
    mov ax, 0AA55h
.verify_p1:
    mov bx, [es:di]
    cmp bx, ax
    jne .data_mismatch
    add di, 2
    add ax, 0001h
    loop .verify_p1

    ; Switch BACK to logical page 0!
    mov dx, [my_handle]
    mov ax, 4400h
    xor bx, bx
    int 67h
    test ah, ah
    jnz .fail_map

    ; Verify Pattern A on logical page 0 is STILL 100% INTACT!
    xor di, di
    mov cx, 8192
    mov ax, 55AAh
.verify_p0:
    mov bx, [es:di]
    cmp bx, ax
    jne .data_mismatch
    add di, 2
    add ax, 0001h
    loop .verify_p0

    ; Step 6: Deallocate handle (AH=45h)
    mov dx, [my_handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz .fail_dealloc

    mov dx, msg_pass
    mov ah, 9
    int 21h

    mov ax, 4C00h
    int 21h

.data_mismatch:
    mov dx, msg_err_mismatch
    mov ah, 9
    int 21h
    jmp .clean_exit

.fail_map:
    mov dx, msg_err_map
    mov ah, 9
    int 21h
    jmp .clean_exit

.fail_dealloc:
    mov dx, msg_err_dealloc
    mov ah, 9
    int 21h

.clean_exit:
    ; Attempt to free handle on failure
    mov dx, [my_handle]
    mov ah, 45h
    int 67h

.fail:
    mov ax, 4C01h
    int 21h

; ---------------------------------------------------------------------------
; Helper: Print Hex Word (AX)
; ---------------------------------------------------------------------------
PrintHex16:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.h_loop:
    rol bx, 4
    mov dl, bl
    and dl, 0Fh
    cmp dl, 9
    jbe .h_num
    add dl, 'A' - 10
    jmp .h_prn
.h_num:
    add dl, '0'
.h_prn:
    mov ah, 2
    int 21h
    loop .h_loop
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; Helper: Print Decimal Word (AX)
; ---------------------------------------------------------------------------
PrintDec16:
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
.d_div:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .d_div
.d_prn:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop .d_prn
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
page_frame_seg  dw 0
my_handle       dw 0

msg_title       db '==================================================', 0Dh, 0Ah
                db ' Next186 LIM EMS 4.0 / 3.2 Hardware Diagnostic', 0Dh, 0Ah
                db '==================================================', 0Dh, 0Ah, '$'

msg_no_emm      db 'FAIL: No Expanded Memory Manager (EMM) detected!', 0Dh, 0Ah, '$'
msg_emm_found   db 'EMM Status: Active and operating normally.', 0Dh, 0Ah, 'Page Frame Base: 0x', '$'
msg_frame_ok    db 'h', 0Dh, 0Ah, '$'
msg_free_pfx    db 'Free Pages: ', '$'
msg_total_pfx   db ' of Total: ', '$'
msg_crlf        db ' (16KB each)', 0Dh, 0Ah, '$'
msg_allocating  db 'Allocating 4 pages (64 KB)... ', '$'
msg_alloc_ok    db 'OK.', 0Dh, 0Ah
                db 'Testing page switching and memory banking integrity...', 0Dh, 0Ah, '$'

msg_pass        db 0Dh, 0Ah
                db '>>> ALL TESTS PASSED! Hardware EMS banking is 100% OPERATIONAL! <<<', 0Dh, 0Ah, '$'

msg_err_frame   db 'FAIL: Could not retrieve Page Frame address!', 0Dh, 0Ah, '$'
msg_err_pages   db 'FAIL: Could not retrieve page counts!', 0Dh, 0Ah, '$'
msg_err_alloc   db 'FAIL: Page allocation failed!', 0Dh, 0Ah, '$'
msg_err_map     db 'FAIL: Page mapping (AH=44h) failed!', 0Dh, 0Ah, '$'
msg_err_mismatch db 'FAIL: Memory data integrity mismatch across bank switch!', 0Dh, 0Ah, '$'
msg_err_dealloc db 'FAIL: Page deallocation (AH=45h) failed!', 0Dh, 0Ah, '$'
