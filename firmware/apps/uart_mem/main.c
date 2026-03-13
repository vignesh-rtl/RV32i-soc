/*
 * test_uart_memory.c - Interactive UART Memory Read/Write
 *
 * This program runs on the RV32I SoC and communicates via UART.
 * It presents a menu to the user:
 *   - Write: User types a word (up to 10 chars), stored in RAM
 *   - Read:  Sends the stored word back over UART
 *
 * UART baud rate: 9600 (set in rv32i_soc.v)
 * Connect with: picocom -b 9600 /dev/ttyUSBx
 */

#include <stdint.h>
#include <rv32i.h>

/* Memory buffer in RAM to store the user's word */
#define MAX_WORD_LEN 10
volatile char stored_word[MAX_WORD_LEN + 1];  /* +1 for null terminator */
volatile uint8_t word_stored = 0;             /* flag: has a word been stored? */

/*
 * Read a single character from UART (blocking — waits until data arrives)
 */
char uart_getchar(void) {
    while (!uart_rx_buffer_full()) {
        /* Wait until a character arrives */
    }
    return uart_read();
}

/*
 * Print a single character over UART
 */
void uart_putchar(char c) {
    volatile uint32_t *uart_tx_data = (volatile uint32_t *) UART_TX_DATA;
    volatile uint32_t *uart_tx_busy = (volatile uint32_t *) UART_TX_BUSY;
    while (*uart_tx_busy);  /* Wait for UART TX to be ready */
    *uart_tx_data = c;
}

/*
 * Print the menu options
 */
void print_menu(void) {
    uart_print("\r\n");
    uart_print("================================\r\n");
    uart_print("  RV32I SoC - Memory Terminal\r\n");
    uart_print("================================\r\n");
    uart_print("  1. Write word to memory\r\n");
    uart_print("  2. Read word from memory\r\n");
    uart_print("================================\r\n");
    uart_print("  Select (1 or 2): ");
}

/*
 * Handle WRITE operation:
 *   - Prompt user for a word (up to 10 characters)
 *   - Store each character into RAM buffer
 *   - Echo each character back as user types
 *   - Enter (CR) or reaching 10 chars ends input
 */
void do_write(void) {
    uart_print("\r\n\r\n  Enter a word (max 10 chars): ");

    uint8_t i = 0;
    while (i < MAX_WORD_LEN) {
        char c = uart_getchar();

        /* Enter key (CR or LF) ends input */
        if (c == '\r' || c == '\n') {
            break;
        }

        /* Backspace support */
        if (c == 0x7F || c == 0x08) {
            if (i > 0) {
                i--;
                uart_print("\b \b");  /* erase character on terminal */
            }
            continue;
        }

        /* Only accept printable ASCII characters */
        if (c >= 0x20 && c <= 0x7E) {
            stored_word[i] = c;
            uart_putchar(c);  /* echo the character back */
            i++;
        }
    }

    /* Null-terminate the string */
    stored_word[i] = '\0';
    word_stored = 1;

    uart_print("\r\n\r\n  >> Stored \"");
    uart_print((char *)stored_word);
    uart_print("\" to memory at address 0x");

    /* Print the address where the word is stored */
    uint32_t addr = (uint32_t)stored_word;
    char hex[9];
    for (int j = 7; j >= 0; j--) {
        uint8_t nibble = addr & 0xF;
        hex[j] = nibble < 10 ? '0' + nibble : 'A' + nibble - 10;
        addr >>= 4;
    }
    hex[8] = '\0';
    uart_print(hex);
    uart_print("\r\n");
}

/*
 * Handle READ operation:
 *   - Read the word stored in RAM buffer
 *   - Send it back over UART
 */
void do_read(void) {
    uart_print("\r\n\r\n  >> Reading from memory: ");

    if (word_stored) {
        uart_print("\"");
        uart_print((char *)stored_word);
        uart_print("\"\r\n");

        /* Also show each byte individually for verification */
        uart_print("  >> Bytes: ");
        for (int i = 0; stored_word[i] != '\0'; i++) {
            char c = stored_word[i];
            /* Print hex value */
            uint8_t hi = (c >> 4) & 0xF;
            uint8_t lo = c & 0xF;
            uart_print("0x");
            uart_putchar(hi < 10 ? '0' + hi : 'A' + hi - 10);
            uart_putchar(lo < 10 ? '0' + lo : 'A' + lo - 10);
            uart_print(" ");
        }
        uart_print("\r\n");
    } else {
        uart_print("[empty - write a word first!]\r\n");
    }
}

/*
 * Main function — runs the interactive menu loop
 */
int main() {
    /* Clear the stored word buffer */
    for (int i = 0; i <= MAX_WORD_LEN; i++) {
        stored_word[i] = 0;
    }

    /* Welcome message */
    uart_print("\r\n\r\n");
    uart_print("  *** RV32I RISC-V SoC ***\r\n");
    uart_print("  UART Memory Read/Write Demo\r\n");
    uart_print("  Baud: 9600 | Clock: 12MHz\r\n");

    /* Main loop — show menu, get choice, execute */
    while (1) {
        print_menu();

        char choice = uart_getchar();
        uart_putchar(choice);  /* echo the choice */

        switch (choice) {
            case '1':
                do_write();
                break;
            case '2':
                do_read();
                break;
            default:
                uart_print("\r\n  Invalid option! Press 1 or 2.\r\n");
                break;
        }
    }

    return 0;
}
