; Тест MINI-8: сумма байта на порту 0 и значения 5, результат на порт 1.
start:
    IN  R0, 0
    LIT R1, 5
    ADD R0, R1
    ST  0x80, R0
    LD  R2, 0x80
    OUT 1, R2
    HALT
