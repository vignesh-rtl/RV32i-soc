/*
 * test_led_blink.c - Timer Interrupt Based LED Blink
 * 
 * This is a bare-metal program that uses the CLINT timer interrupt
 * to blink LEDs on the Cmod-S7 board periodically.
 *
 * Modified for 250ms blinking.
 *
 * LED mapping (from XDC):
 *   gpio_pins[8]  → LED1 (pin E2)
 *   gpio_pins[9]  → LED2 (pin K1)
 *   gpio_pins[10] → LED3 (pin J1)
 *   gpio_pins[11] → LED4 (pin E1)
 *
 * CLINT memory map:
 *   0x80000000 → mtime (64-bit timer counter)
 *   0x80000008 → mtimecmp (64-bit compare register)
 *   0x80000010 → msip (software interrupt pending)
 *
 * Clock: 12 MHz → 12,000,000 ticks per second
 *        250ms = 3,000,000 ticks
 */

#include <stdint.h>
#include <rv32i.h>

/* LED pin numbers (gpio_pins index) */
#define LED1  8
#define LED2  9
#define LED3  10
#define LED4  11

/* Blink interval in milliseconds */
#define BLINK_INTERVAL_MS  250

/* Global variable to track which LED pattern to show */
volatile uint32_t led_state = 0;

/*
 * Trap handler — called automatically on any interrupt/exception.
 * The __attribute__((interrupt)) tells the compiler to save/restore
 * all registers and use MRET to return.
 */
void __attribute__((interrupt)) trap_handler(void) {
    /* Read mcause to determine why we trapped */
    uint32_t mcause;
    asm volatile("csrr %0, mcause" : "=r"(mcause));

    /* Check if this is a timer interrupt (mcause = 0x80000007) */
    if (mcause == 0x80000007) {
        /* Toggle LED pattern */
        led_state++;

        /* Set LEDs based on state — creates a walking pattern */
        uint32_t led_pattern = 0;
        switch (led_state % 4) {
            case 0: led_pattern = (1 << LED1); break;                     /* LED1 only */
            case 1: led_pattern = (1 << LED2); break;                     /* LED2 only */
            case 2: led_pattern = (1 << LED3); break;                     /* LED3 only */
            case 3: led_pattern = (1 << LED4); break;                     /* LED4 only */
        }

        /* Set all LED pins to write mode and write the pattern */
        uint32_t mode = gpio_read_mode();
        mode |= (1 << LED1) | (1 << LED2) | (1 << LED3) | (1 << LED4);
        gpio_set_mode(mode);
        
        /* Read current GPIO, clear LED bits, set new pattern */
        uint32_t current = gpio_write_value();
        current &= ~((1 << LED1) | (1 << LED2) | (1 << LED3) | (1 << LED4));
        current |= led_pattern;
        gpio_write(current);

        /* Set the next timer compare value (current time + interval) */
        uint64_t next_cmp = mtime_get_time() + ms_to_cpu_ticks(BLINK_INTERVAL_MS);
        mtime_set_timecmp(next_cmp);
    }
}

int main() {
    /* Step 1: Setup the trap handler */
    trap_handler_setup(trap_handler);

    /* Step 2: Initialize all LEDs to OFF */
    /* Set LED pins (8,9,10,11) to write mode */
    uint32_t mode = gpio_read_mode();
    mode |= (1 << LED1) | (1 << LED2) | (1 << LED3) | (1 << LED4);
    gpio_set_mode(mode);
    gpio_write(0); /* All LEDs off initially */

    /* Step 3: Reset the timer */
    mtime_set_time(0);

    /* Step 4: Set the first timer compare value (fire after BLINK_INTERVAL_MS) */
    mtime_set_timecmp(ms_to_cpu_ticks(BLINK_INTERVAL_MS));

    /* Step 5: Enable timer interrupt in MIE register (bit 7 = MTIE) */
    csr_set(MIE, (1 << MIE_MTIE));

    /* Step 6: Enable global interrupts in MSTATUS (bit 3 = MIE) */
    csr_set(MSTATUS, (1 << MSTATUS_MIE));

    /* Step 7: Main loop — do nothing, timer interrupt handles everything */
    while (1) {
        /* CPU idles here. Every 250ms the timer interrupt fires,
           the trap_handler toggles LEDs and resets the timer. */
    }

    return 0;
}
