extends Node

# Наблюдатели не участвуют в арбитраже. Регистры и показания передаются копиями.
signal on_tick(tick: int)
signal on_signal_change(tick: int, net: String, sample: Dictionary)
signal on_instruction(tick: int, chip: String, pc: int, mnemonic: String, registers: Array)
signal timeline_reset(tick: int)
