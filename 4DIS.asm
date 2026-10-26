 list p=16f887
 #include <p16f887.inc>

__CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _LVP_OFF
__CONFIG _CONFIG2, _BOR_OFF

;variables
contador        EQU     0x20        ; centesimas 0..99
unidades        EQU     0x21        ; CC unidades
decenas         EQU     0x22        ; CC decenas
ESTADO_BOTON    EQU     0x23        ; estado estable del pulsador
PATRON_TEMP     EQU     0x24        ; patron de 7 segmentos
PORTC_TEMP      EQU     0x25        ; conserva RC6 y RC7
PORTE_TEMP      EQU     0x26        ; prepara RE0, RE1 y RE2
seg_unidades    EQU     0x29        ; segundos unidades
seg_decenas     EQU     0x2A        ; segundos decenas
MARCHA          EQU     0x2B        ; 1 = cronometro contando
PAUSA           EQU     0x2C        ; 1 = cronometro pausado
REB_ACTIVA      EQU     0x2D        ; 1 = antirrebote activo
CONT_REB        EQU     0x2E        ; tiempo restante del antirrebote
DURACION_PRES   EQU     0x2F        ; duracion de la pulsacion
PULS_LARGA      EQU     0x30        ; 1 = ya se atendio la larga
DIGITO_SEL      EQU     0x31        ; display a refrescar, 0..3
VALOR_TEMP      EQU     0x32        ; digito temporal
DIV_TICK        EQU     0x33        ; cuenta 4 ticks rapidos para formar ~10 ms

;constantes, parámetros del antirrebote y de la base de tiempo de Timer0.
N_REB           EQU     .2          ;aprox. 20 ms
N_TMR0          EQU     .100        ;precarga: ~2,496 ms con prescaler 1:16

;variables para preservar el contexto de la ISR
        CBLOCK  0x70
W_TEMP
STATUS_TEMP
PCLATH_TEMP
        ENDC

;vector de reset
        ORG     0x0000
        GOTO    main

;vector de interrupcion
        ORG     0x0004
        MOVWF   W_TEMP
        SWAPF   STATUS,W
        MOVWF   STATUS_TEMP
        MOVF    PCLATH,W
        MOVWF   PCLATH_TEMP
        CLRF    PCLATH

        BANKSEL INTCON
        BTFSC   INTCON,T0IF
        CALL    ISR_TMR0

SALIR_ISR:                  ;restaura contexto y sale de la ISR
        MOVF    PCLATH_TEMP,W
        MOVWF   PCLATH
        SWAPF   STATUS_TEMP,W
        MOVWF   STATUS
        SWAPF   W_TEMP,F
        SWAPF   W_TEMP,W
        RETFIE

	ORG     0x0020
main:                       ;configuracion inicial
        BANKSEL INTCON
        CLRF    INTCON

        BANKSEL ANSEL
        CLRF    ANSEL           ;puertos analogicos a digital
        CLRF    ANSELH

        BANKSEL TRISA
        MOVLW   b'11110000'
        MOVWF   TRISA           ;RA0..RA3 selectores

        MOVLW   b'11000000'
        MOVWF   TRISC           ;RC0..RC5 segmentos a..f

        BANKSEL TRISD
        MOVLW   b'11111111'
        MOVWF   TRISD           ;PORTD no se utiliza

        MOVLW   b'11111100'
        MOVWF   TRISE           ;RE0=g, RE1=dp, RE2=pulsador
        BSF     TRISE,2

        BANKSEL PORTA
        CLRF    PORTA           ;selectores apagados al iniciar
        CLRF    PORTC           ;segmentos en cero
        CLRF    PORTD           ;PORTD sin uso
        CLRF    PORTE           ;g, dp y resto de PORTE en cero

        BANKSEL contador
        CLRF    contador
        CLRF    unidades
        CLRF    decenas
        CLRF    ESTADO_BOTON
        CLRF    PATRON_TEMP
        CLRF    PORTC_TEMP
        CLRF    PORTE_TEMP
        CLRF    seg_unidades
        CLRF    seg_decenas
        CLRF    MARCHA
        CLRF    PAUSA
        CLRF    REB_ACTIVA
        CLRF    CONT_REB
        CLRF    DURACION_PRES
        CLRF    PULS_LARGA
        CLRF    DIGITO_SEL
        CLRF    VALOR_TEMP
        CLRF    DIV_TICK          ; inicia el divisor de tiempo en cero

        BANKSEL OPTION_REG       ;configuracion de Timer0
        MOVLW   b'10000011'
        MOVWF   OPTION_REG       ;reloj Fosc/4, prescaler 1:16

        BANKSEL TMR0             ;registro de Timer0
        MOVLW   N_TMR0
        MOVWF   TMR0             ;con 4 MHz: aprox. 2,496 ms por desborde

        BANKSEL INTCON
        BCF     INTCON,T0IF      ;limpia bandera de desborde pendiente
        BSF     INTCON,T0IE      ;habilita interrupción de Timer0
        BSF     INTCON,GIE       ;habilita las interrupciones globales
    
;no hay retardos ni espera de liberación: Timer0 realiza las tareas temporales.
Loop_Principal:                ;lazo principal vacio.
        GOTO    Loop_Principal

;Timer0 refresca un display cada ~2,5 ms; cada cuatro ticks se atienden conteo y pulsador.
ISR_TMR0:                       ;servicio del desborde de Timer0
        BANKSEL TMR0            ;registro de Timer0
        MOVLW   N_TMR0
        MOVWF   TMR0             ;recarga para el siguiente tick de ~2,5 ms

        BANKSEL INTCON
        BCF     INTCON,T0IF      ;limpia bandera de desborde pendiente

        CALL    MUX_DISPLAYS     ;refresca un display en cada interrupcion

        ; Cuatro ticks de ~2,5 ms forman un tick logico de ~10 ms.
        ; Asi se acelera el barrido sin acelerar el cronometro ni el pulsador.
        BANKSEL DIV_TICK
        INCF    DIV_TICK,F
        MOVLW   .4
        SUBWF   DIV_TICK,W
        BTFSS   STATUS,Z
        RETURN                  ; aun no transcurrieron aproximadamente 10 ms

        CLRF    DIV_TICK        ; reinicia el divisor para el siguiente tick logico

        BTFSC   MARCHA,0
        CALL    ACTUALIZAR_CRONO ; actualiza el tiempo solo cuando esta en marcha

        CALL    TECLA_TICK       ; conserva la base de ~10 ms para antirrebote y pulsacion
        RETURN

;se apagan todos, se actualizan segmentos y se habilita un solo CAT.
MUX_DISPLAYS:                   ;multiplexa los 4 displays
        BANKSEL PORTA
        BCF     PORTA,0
        BCF     PORTA,1
        BCF     PORTA,2
        BCF     PORTA,3

        BANKSEL DIGITO_SEL
        MOVF    DIGITO_SEL,W
        BTFSC   STATUS,Z
        GOTO    MUX_CC_UNIDADES

        MOVLW   .1
        SUBWF   DIGITO_SEL,W
        BTFSC   STATUS,Z
        GOTO    MUX_CC_DECENAS

        MOVLW   .2
        SUBWF   DIGITO_SEL,W
        BTFSC   STATUS,Z
        GOTO    MUX_SS_UNIDADES

        GOTO    MUX_SS_DECENAS

MUX_CC_UNIDADES:                ;RA0 -> CAT1 -> CC unidades
        MOVF    unidades,W
        CALL    MOSTRAR_VALOR
        BANKSEL PORTA
        BSF     PORTA,0
        GOTO    MUX_SIGUIENTE

MUX_CC_DECENAS:                 ;RA1 -> CAT2 -> CC decenas
        MOVF    decenas,W
        CALL    MOSTRAR_VALOR
        BANKSEL PORTA
        BSF     PORTA,1
        GOTO    MUX_SIGUIENTE

MUX_SS_UNIDADES:                ;RA2 -> CAT3 -> SS unidades
        MOVF    seg_unidades,W
        CALL    MOSTRAR_VALOR
        BANKSEL PORTA
        BSF     PORTA,2
        GOTO    MUX_SIGUIENTE

MUX_SS_DECENAS:                 ;RA3 -> CAT4 -> SS decenas
        MOVF    seg_decenas,W
        CALL    MOSTRAR_VALOR
        BANKSEL PORTA
        BSF     PORTA,3

;secuencia: CAT1 -> CAT2 -> CAT3 -> CAT4 -> CAT1...
MUX_SIGUIENTE:                  ;pasa al siguiente display
        BANKSEL DIGITO_SEL
        INCF    DIGITO_SEL,F
        MOVLW   .4
        SUBWF   DIGITO_SEL,W
        BTFSC   STATUS,Z
        CLRF    DIGITO_SEL
        RETURN
;se obtiene de la tabla el patrón correspondiente al display.
MOSTRAR_VALOR:                  ;W contiene un digito 0..9
        MOVWF   VALOR_TEMP
        MOVLW   HIGH TABLA_7SEG
        MOVWF   PCLATH
        MOVF    VALOR_TEMP,W
        CALL    TABLA_7SEG
        CLRF    PCLATH
        CALL    Enviar_Segmentos
        RETURN

Enviar_Segmentos:               ;envia el patron al bus de segmentos
        MOVWF   PATRON_TEMP

        BANKSEL PORTC
        MOVF    PORTC,W
        ANDLW   0xC0
        MOVWF   PORTC_TEMP

        MOVF    PATRON_TEMP,W
        ANDLW   0x3F
        IORWF   PORTC_TEMP,W
        MOVWF   PORTC

        CLRF    PORTE_TEMP
        BTFSC   PATRON_TEMP,6
        BSF     PORTE_TEMP,0
        BTFSC   PATRON_TEMP,7
        BSF     PORTE_TEMP,1

        BANKSEL PORTE
        BTFSC   PORTE,2
        BSF     PORTE_TEMP,2

        MOVF    PORTE_TEMP,W
        MOVWF   PORTE
        RETURN

;actualiza las centesimas con cada tick logico; aprox. 100 ticks de 10 ms forman 1 s.
ACTUALIZAR_CRONO:               ;suma una centesima aprox. cada 10 ms logicos
        BANKSEL contador
        INCF    contador,F

        MOVLW   .100
        SUBWF   contador,W
        BTFSC   STATUS,Z
        GOTO    NUEVO_SEGUNDO

        INCF    unidades,F
        MOVLW   .10
        SUBWF   unidades,W
        BTFSS   STATUS,Z
        RETURN

        CLRF    unidades
        INCF    decenas,F
        RETURN

;CC vuelve a 00 y se incrementan los segundos.
NUEVO_SEGUNDO:                   ;99 centesimas -> aumenta 1 segundo
        CLRF    contador
        CLRF    unidades
        CLRF    decenas

        INCF    seg_unidades,F
        MOVLW   .10
        SUBWF   seg_unidades,W
        BTFSS   STATUS,Z
        RETURN

        CLRF    seg_unidades
        INCF    seg_decenas,F
        MOVLW   .6
        SUBWF   seg_decenas,W
        BTFSS   STATUS,Z
        RETURN

        CLRF    seg_decenas       ;59:99 -> 00:00
        RETURN
	
;se usa al iniciar y para la acción de pulsación larga.
PONER_CERO:                     ;pone el cronometro en 00:00
        BANKSEL contador
        CLRF    contador
        CLRF    unidades
        CLRF    decenas
        CLRF    seg_unidades
        CLRF    seg_decenas
        RETURN

;RE2=0: presionado. RE2=1: liberado. La rutina se consulta cada ~10 ms logicos.
TECLA_TICK:                     ;muestrea RE2 y procesa la pulsacion
        BTFSS   PORTE,2
        GOTO    TECLA_RAW_BAJA

        BTFSC   ESTADO_BOTON,0
        GOTO    CAMBIO_A_LIBERADO

        BCF     REB_ACTIVA,0
        RETURN

;se inicia el antirrebote antes de aceptar la presión.
TECLA_RAW_BAJA:                 ;posible pulsacion nueva
        BTFSC   ESTADO_BOTON,0
        GOTO    PRESION_ESTABLE

        BTFSC   REB_ACTIVA,0
        GOTO    REB_PRESION_CONT

        BSF     REB_ACTIVA,0
        MOVLW   N_REB
        MOVWF   CONT_REB
        RETURN

;al vencer el contador se vuelve a leer RE2 una sola vez.
REB_PRESION_CONT:               ;termina antirrebote de presion
        DECFSZ  CONT_REB,F
        RETURN

        BCF     REB_ACTIVA,0
        BTFSC   PORTE,2
        RETURN

        BSF     ESTADO_BOTON,0
        CLRF    DURACION_PRES
        BCF     PULS_LARGA,0
        RETURN

;aquí se mide la duración para distinguir corta de larga.
PRESION_ESTABLE:                ;boton sigue presionado
        BCF     REB_ACTIVA,0

;100 ticks representan aprox. 1 segundo.
CONTAR_DURACION:                ;mide cuanto tiempo permanece pulsado
        BTFSC   PULS_LARGA,0
        RETURN

        INCF    DURACION_PRES,F
        MOVLW   .100
        SUBWF   DURACION_PRES,W
        BTFSC   STATUS,Z
        CALL    PULSACION_LARGA
        RETURN

CAMBIO_A_LIBERADO:             ;posible liberacion, también pasa por el antirr.
        BTFSC   REB_ACTIVA,0
        GOTO    REB_LIBERACION_CONT

        BSF     REB_ACTIVA,0
        MOVLW   N_REB
        MOVWF   CONT_REB
        GOTO    CONTAR_DURACION

REB_LIBERACION_CONT:            ;termina antirrebote de liberacion
        DECFSZ  CONT_REB,F
        GOTO    CONTAR_DURACION

        BCF     REB_ACTIVA,0
        BTFSS   PORTE,2
        GOTO    PRESION_ESTABLE

        BCF     ESTADO_BOTON,0

        BTFSC   PULS_LARGA,0
        GOTO    FIN_LIBERACION

        CALL    PULSACION_CORTA

FIN_LIBERACION:                 ;evita una accion al soltar despues de larga
        BCF     PULS_LARGA,0
        CLRF    DURACION_PRES
        RETURN

;detenido -> inicia en cero. Contando -> pausa. Pausado -> reanuda.
PULSACION_CORTA:                ;corta: inicia, pausa o reanuda
        BTFSC   MARCHA,0
        GOTO    CORTA_PAUSAR

        BTFSC   PAUSA,0
        GOTO    CORTA_REANUDAR

CORTA_INICIAR:                  ;detenido -> inicia desde cero
        CALL    PONER_CERO
        BSF     MARCHA,0
        BCF     PAUSA,0
        RETURN

CORTA_PAUSAR:                   ;contando -> pausa
        BCF     MARCHA,0
        BSF     PAUSA,0
        RETURN

CORTA_REANUDAR:                 ;pausado -> reanuda
        BSF     MARCHA,0
        BCF     PAUSA,0
        RETURN

;se ejecuta una sola vez y la liberación posterior no genera otra acción.
PULSACION_LARGA:                ; larga -> detiene y pone en cero
        BSF     PULS_LARGA,0
        BCF     MARCHA,0
        BCF     PAUSA,0
        CALL    PONER_CERO
        RETURN

;tabla de decodificacion
        ORG     0x0300
TABLA_7SEG:                     ;codigos para display de catodo comun
        ADDWF   PCL,F           ;suma el desplazamiento en W al PCL
        RETLW   0x3F            ; código para el 0 (abcdef)
        RETLW   0x06            ; código para el 1 (bc)
        RETLW   0x5B            ; código para el 2 (abdeg)
        RETLW   0x4F            ; código para el 3 (abcdg)
        RETLW   0x66            ; código para el 4 (bcfg)
        RETLW   0x6D            ; código para el 5 (acdfg)
        RETLW   0x7D            ; código para el 6 (acdefg)
        RETLW   0x07            ; código para el 7 (abc)
        RETLW   0x7F            ; código para el 8 (abcdefg)
        RETLW   0x6F            ; código para el 9 (abcdfg)

        END

