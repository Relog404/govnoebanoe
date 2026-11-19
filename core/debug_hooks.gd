extends Node

# Наблюдатели не участвуют в арбитраже. Регистры и показания передаются копиями.
@warning_ignore("unused_signal")
signal on_tick(tick: int)
@warning_ignore("unused_signal")
signal on_signal_change(tick: int, net: String, sample: Dictionary)
@warning_ignore("unused_signal")
signal on_instruction(tick: int, chip: String, pc: int, mnemonic: String, registers: Array)
@warning_ignore("unused_signal")
signal timeline_reset(tick: int)
