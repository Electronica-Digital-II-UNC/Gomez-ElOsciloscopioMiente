list p=16f887
include "P16f887.INC"

    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON
    __CONFIG _CONFIG2, _LVP_OFF & _BOR_OFF
    
; vector de reset
ORG     0x00
GOTO    main

;  mapa de memoria 
SALIDA_D    EQU 0x20    ; contador 
ESTADO      EQU 0x21    ; 0 = contador, 1 = secuencia de luces
TIEMPO      EQU 0x22    ; mide duración de pulsación (en bloques de 100ms)
SEC_LUCES   EQU 0x23    ; secuencia de los LEDs
DIR_LUCES   EQU 0x24    ; 0 = izquierda, 1 = derecha
PAUSA       EQU 0x25    ; 0 = activo, 1 = detenido
CONT1       EQU 0x26    ; contador para el bucle de retardo
CONT2       EQU 0x27    ; cintador secundario de retardo
CONT_SEC    EQU 0x28    ; contador para velocidad de luces

ORG 0x20
main:
    ; deshabilitar entradas analogicas (todas a digital)
    BANKSEL ANSEL
    CLRF    ANSEL
    CLRF    ANSELH

    BANKSEL PORTD
    CLRF    PORTD

    BANKSEL TRISD
    CLRF    TRISD       ; PORTD como salida
    BSF     TRISB, 0    ; RB0 como entrada

    ; habilitar pullUp interna en RB0
    BANKSEL OPTION_REG
    BCF     OPTION_REG, 7 
    BANKSEL WPUB
    BSF     WPUB, 0       

    ;inicializar variables (Estado 0)
    BANKSEL SALIDA_D
    CLRF    SALIDA_D
    CLRF    ESTADO
    MOVLW   d'100'
    MOVWF   CONT_SEC    ; velocidad inicial de la secuencia

; linea principal del flujo
LINEA_PRINCIPAL:
    ; revisar si hay presión en el botón
    BANKSEL PORTB
    BTFSS   PORTB, 0    ; si es 0 (presionado), salta a leer tiempo
    GOTO    PROCESAR_PULSACION

    ; si no hay presión, procesar secuencia (solo si estado = 1)
    BANKSEL ESTADO
    BTFSS   ESTADO, 0
    GOTO    LINEA_PRINCIPAL ; si es estado 0, solo esperar botón

    BTFSC   PAUSA, 0
    GOTO    LINEA_PRINCIPAL ; si está pausado, no mueve los LEDs

    ; contador de la secuencia
    DECFSZ  CONT_SEC, F
    GOTO    ESPERA_BOTON ; si no llegó a 0, sigue leyendo botón
    MOVLW   d'50'          
    MOVWF   CONT_SEC       ; recarga la velocidad de los LEDs

    ; ejecutar desplazamiento
    BTFSC   DIR_LUCES, 0
    GOTO    MOVER_DERECHA

MOVER_IZQUIERDA:
    BCF     STATUS, C
    RLF     SEC_LUCES, F
    BTFSS   STATUS, C
    GOTO    ACTUALIZAR_PUERTO
    BSF     SEC_LUCES, 0   ; reinicia el bit si desbordó
    GOTO    ACTUALIZAR_PUERTO

MOVER_DERECHA:
    BCF     STATUS, C
    RRF     SEC_LUCES, F
    BTFSS   STATUS, C
    GOTO    ACTUALIZAR_PUERTO
    BSF     SEC_LUCES, 7   ; reinicia el bit si desbordó

ACTUALIZAR_PUERTO:
    MOVF    SEC_LUCES, W
    BANKSEL PORTD
    MOVWF   PORTD

ESPERA_BOTON:
    CALL    RETARDO_5MS     ; espera para que el programa no corra tan rápido
    GOTO    LINEA_PRINCIPAL

; lógica de pulsación (filtro antirrebote y mediciónes)
PROCESAR_PULSACION:
    CALL    RETARDO_20MS   ; antirrebote 
    BANKSEL PORTB
    BTFSC   PORTB, 0
    GOTO    LINEA_PRINCIPAL ; retorna si fue ruido mecánico

    BANKSEL TIEMPO
    CLRF    TIEMPO

MANTENIENDO_PULSACION:
    BANKSEL PORTB
    BTFSC   PORTB, 0       ; verifica si se soltó el botón
    GOTO    EVALUAR_FLUJO  ; si se soltó, evalúa las decisiones

    CALL    RETARDO_100MS
    BANKSEL TIEMPO
    INCF    TIEMPO, F
    MOVF    TIEMPO, W
    SUBLW   d'40'          ; límite de 4s para evitar desbordamiento
    BTFSC   STATUS, Z
    DECF    TIEMPO, F      ; mantiene el tiempo estancado en 40
    GOTO    MANTENIENDO_PULSACION

EVALUAR_FLUJO:
    BANKSEL ESTADO
    BTFSC   ESTADO, 0
    GOTO    EVALUAR_ESTADO_1

EVALUAR_ESTADO_0:
    ; ¿pulsación >= 3s (30 décimas)?
    MOVF    TIEMPO, W
    SUBLW   d'29'
    BTFSS   STATUS, C      ; C=0 si TIEMPO >= 30
    GOTO    IR_A_ESTADO_1

    ; pulsación (< 3s): incrementa contador
    INCF    SALIDA_D, F
    MOVF    SALIDA_D, W
    BANKSEL PORTD
    MOVWF   PORTD
    GOTO    LINEA_PRINCIPAL

EVALUAR_ESTADO_1:
    ; ¿pulsación >= 3s?
    MOVF    TIEMPO, W
    SUBLW   d'29'
    BTFSS   STATUS, C
    GOTO    IR_A_ESTADO_0

    ; ¿pulsación <= 1.5s (15 décimas)?
    MOVF    TIEMPO, W
    SUBLW   d'15'
    BTFSC   STATUS, C      ; C=1 si TIEMPO <= 15
    GOTO    TOGGLE_PAUSA

    ; pulsación entre 1.5s y 3s: cambiar dirección
    MOVLW   0x01
    XORWF   DIR_LUCES, F   ; invierte el estado de la dirección
    GOTO    LINEA_PRINCIPAL

CAMBIAR_PAUSA:
    MOVLW   0x01
    XORWF   PAUSA, F       ; cambia de 0 a 1 o de 1 a 0 para pausar
    GOTO    LINEA_PRINCIPAL

;transciciones de estados 
IR_A_ESTADO_1:
    BSF     ESTADO, 0      ; pasa a Estado = 1
    MOVLW   0x01
    MOVWF   SEC_LUCES      ; inicia LED en el primer bit
    CLRF    DIR_LUCES      ; dirección izquierda
    CLRF    PAUSA          ; arranca sin pausa
    MOVF    SEC_LUCES, W
    BANKSEL PORTD
    MOVWF   PORTD
    GOTO    LINEA_PRINCIPAL

IR_A_ESTADO_0:
    CLRF    ESTADO         ; vuelve al Estado = 0
    CLRF    SALIDA_D       ; reinicia contador binario
    MOVF    SALIDA_D, W
    BANKSEL PORTD
    MOVWF   PORTD
    GOTO    LINEA_PRINCIPAL

; subrutinas de retardo (4MHz)
RETARDO_5MS:
    MOVLW   d'65'
    MOVWF   CONT1
R_5MS_LOOP:
    MOVLW   d'25'
    MOVWF   CONT2
    DECFSZ  CONT2, F
    GOTO    $-1
    DECFSZ  CONT1, F
    GOTO    R_5MS_LOOP
    RETURN

RETARDO_20MS:
    CALL    RETARDO_5MS
    CALL    RETARDO_5MS
    CALL    RETARDO_5MS
    CALL    RETARDO_5MS
    RETURN

RETARDO_100MS:
    CALL    RETARDO_20MS
    CALL    RETARDO_20MS
    CALL    RETARDO_20MS
    CALL    RETARDO_20MS
    CALL    RETARDO_20MS
    RETURN

    END
    