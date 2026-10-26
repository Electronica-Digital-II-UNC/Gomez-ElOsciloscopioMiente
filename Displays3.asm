
    list p=16f887
    #include <p16f887.inc>

    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _LVP_OFF
    __CONFIG _CONFIG2, _BOR_OFF

; variables
contador     EQU     0x20        ; guarda el valor en binario
unidades     EQU     0x21        ; para el 1er display
decenas      EQU     0x22        ; para el 2do display
ESTADO_BOTON EQU     0x23        ; memoriza el estado de la pulsacion
PATRON_TEMP  EQU     0x24        ; para el mapeo de los 7 segmentos
PORTC_TEMP   EQU     0x25        ; conservar otras salidas del puerto C
PORTE_TEMP   EQU     0x26        ; preparar las salidas del puerto E
REG_MS       EQU     0x27        ; retardo en milisegundos
REG_US       EQU     0x28        ; retardo interno
DEB_CONT     EQU     0x29        ; contador de muestras antirrebote

; vector de reset
    ORG     0x00
    GOTO    main

; vector de interrupcion
    ORG     0x0004
    RETFIE

    ORG     0x0020

main:
    BANKSEL ANSEL
    CLRF    ANSEL               ; desactivar entradas analogicas
    CLRF    ANSELH

    BANKSEL TRISA
    BCF     TRISA, 0            ; RA0: seleccion de unidades D0
    BCF     TRISA, 1            ; RA1: seleccion de decenas D1

    MOVLW   b'11000000'
    MOVWF   TRISC               ; RC0-RC5 salidas para segmentos a-f

    CLRF    TRISD               ; PORTD como salida para los LEDs

    MOVLW   b'11111100'
    MOVWF   TRISE               ; RE0 y RE1 salidas; RE2 entrada
    BSF     TRISE, 2            ; RE2 como entrada para el pulsador

    ; inicializar puertos y variables
    BANKSEL PORTA
    CLRF    PORTA
    CLRF    PORTC
    CLRF    PORTD
    CLRF    PORTE

    BANKSEL contador
    CLRF    contador
    CLRF    unidades
    CLRF    decenas
    CLRF    ESTADO_BOTON
    CLRF    DEB_CONT

    ; iniciar contador en 00
    CALL    Convertir_Bin_Dec
    MOVF    contador, W
    MOVWF   PORTD

Loop_Multiplexado:
    ; 1. apagar displays antes de cambiar segmentos
    BANKSEL PORTA
    BCF     PORTA, 0
    BCF     PORTA, 1

    ; 2. mostrar unidades en D0
    BANKSEL unidades
    MOVLW   HIGH TABLA_7SEG
    MOVWF   PCLATH
    MOVF    unidades, W
    CALL    TABLA_7SEG
    CALL    Enviar_Segmentos

    BANKSEL PORTA
    BSF     PORTA, 0            ; habilitar D0
    CALL    RETARDO_3MS

    ; 3. apagar displays antes de cambiar segmentos
    BCF     PORTA, 0
    BCF     PORTA, 1

    ; 4. mostrar decenas en D1
    BANKSEL decenas
    MOVLW   HIGH TABLA_7SEG
    MOVWF   PCLATH
    MOVF    decenas, W
    CALL    TABLA_7SEG
    CALL    Enviar_Segmentos

    BANKSEL PORTA
    BSF     PORTA, 1            ; habilitar D1
    CALL    RETARDO_3MS

; lectura del pulsador con antirrebote
Loop_Pulsador:
    BANKSEL PORTE
    BTFSC   PORTE, 2            ; si RE2 = 1, boton liberado
    GOTO    Boton_Liberado

    ; RE2 = 0: posible pulsacion
    BANKSEL ESTADO_BOTON
    BTFSC   ESTADO_BOTON, 0
    GOTO    Boton_Ya_Presionado

    ; confirmar cuatro muestras bajas consecutivas
    INCF    DEB_CONT, F
    MOVLW   d'4'
    SUBWF   DEB_CONT, W
    BTFSS   STATUS, Z
    GOTO    Seguir_Loop

    ; pulsacion confirmada: registrar una sola vez
    BSF     ESTADO_BOTON, 0
    CLRF    DEB_CONT

    ; incrementar contador binario
    BANKSEL contador
    INCF    contador, F

    ; volver a 00 al llegar a 100
    MOVLW   d'100'
    SUBWF   contador, W
    BTFSC   STATUS, Z
    CLRF    contador

    ; actualizar el banco de LEDs
    MOVF    contador, W
    MOVWF   PORTD

    ; convertir el valor binario a decenas y unidades
    CALL    Convertir_Bin_Dec
    GOTO    Seguir_Loop

Boton_Ya_Presionado:
    ; no repetir el incremento mientras siga presionado
    ; reiniciar la cuenta de muestras de liberacion
    CLRF    DEB_CONT
    GOTO    Seguir_Loop

Boton_Liberado:
    BANKSEL ESTADO_BOTON
    BTFSS   ESTADO_BOTON, 0
    GOTO    Boton_Sin_Pulsar

    ; confirmar cuatro muestras altas consecutivas
    INCF    DEB_CONT, F
    MOVLW   d'4'
    SUBWF   DEB_CONT, W
    BTFSS   STATUS, Z
    GOTO    Seguir_Loop

    ; liberacion confirmada: habilitar otra pulsacion
    BCF     ESTADO_BOTON, 0
    CLRF    DEB_CONT
    GOTO    Seguir_Loop

Boton_Sin_Pulsar:
    ; sin pulsacion registrada: esperar al siguiente ciclo
    CLRF    DEB_CONT

Seguir_Loop:
    GOTO    Loop_Multiplexado

; subrutina de conversion binario a decimal
Convertir_Bin_Dec:
    CLRF    decenas
    MOVF    contador, W
    MOVWF   unidades

Resta_10:
    MOVLW   d'10'
    SUBWF   unidades, W         ; W = unidades - 10
    BTFSS   STATUS, C           ; C = 0 si el valor es menor que 10
    GOTO    Fin_Conversion
    MOVWF   unidades
    INCF    decenas, F
    GOTO    Resta_10

Fin_Conversion:
    RETURN

; subrutina para enviar los segmentos a los displays
Enviar_Segmentos:
    MOVWF   PATRON_TEMP

    BANKSEL PORTC
    MOVF    PORTC, W
    ANDLW   0xC0                ; conservar RC6 y RC7
    MOVWF   PORTC_TEMP

    MOVF    PATRON_TEMP, W
    ANDLW   0x3F                ; segmentos a-f en RC0-RC5
    IORWF   PORTC_TEMP, W
    MOVWF   PORTC

    CLRF    PORTE_TEMP
    BTFSC   PATRON_TEMP, 6      ; comprobar segmento g
    BSF     PORTE_TEMP, 0       ; RE0 = 1

    BTFSC   PATRON_TEMP, 7      ; comprobar punto decimal
    BSF     PORTE_TEMP, 1       ; RE1 = 1

    ; conservar el nivel leido de RE2
    BANKSEL PORTE
    BTFSC   PORTE, 2
    BSF     PORTE_TEMP, 2

    MOVF    PORTE_TEMP, W
    MOVWF   PORTE
    RETURN

; subrutina de retardo de 3 ms
RETARDO_3MS:
    MOVLW   d'3'
    MOVWF   REG_MS

loop_ms:
    MOVLW   d'249'
    MOVWF   REG_US

loop_us:
    NOP
    DECFSZ  REG_US, F
    GOTO    loop_us
    DECFSZ  REG_MS, F
    GOTO    loop_ms
    RETURN

; tabla de decodificacion de 7 segmentos
    ORG     0x0300

TABLA_7SEG:
    ADDWF   PCL, F
    RETLW   0x3F                ; 0: abcdef
    RETLW   0x06                ; 1: bc
    RETLW   0x5B                ; 2: abdeg
    RETLW   0x4F                ; 3: abcdg
    RETLW   0x66                ; 4: bcfg
    RETLW   0x6D                ; 5: acdfg
    RETLW   0x7D                ; 6: acdefg
    RETLW   0x07                ; 7: abc
    RETLW   0x7F                ; 8: abcdefg
    RETLW   0x6F                ; 9: abcdfg

    END
