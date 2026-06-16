#include <stdint.h>

#define UART_TX_DATA        (*((volatile uint32_t*) 0x80000050))
#define UART_TX_BUSY        (*((volatile uint32_t*) 0x80000054))

#define AXI_PWM_PERIOD      (*((volatile uint32_t*) 0x80000100))
#define AXI_PWM_DUTY        (*((volatile uint32_t*) 0x80000104))

void my_uart_putchar(char c) {
    while (UART_TX_BUSY) {}
    UART_TX_DATA = c;
}

void my_uart_print(const char* str) {
    while (*str) {
        my_uart_putchar(*str++);
    }
}

void delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        __asm__("nop");
    }
}

int main() {
    my_uart_print("\r\n=================================\r\n");
    my_uart_print("   AXI PWM DIAGNOSTIC TEST       \r\n");
    my_uart_print("=================================\r\n");
    
    my_uart_print("Setting PWM Period to 12000...\r\n");
    AXI_PWM_PERIOD = 12000;
    
    my_uart_print("Entering loop!\r\n");

    uint32_t duty = 0;
    int direction = 1; 

    while (1) {
        AXI_PWM_DUTY = duty;

        if (duty == 0) my_uart_print("Duty = 0\r\n");
        if (duty == 6000) my_uart_print("Duty = 6000\r\n");
        if (duty == 12000) my_uart_print("Duty = 12000\r\n");

        if (direction == 1) {
            duty += 1000; // Faster steps for diagnostic
            if (duty >= 12000) {
                duty = 12000;
                direction = -1; 
                delay(100000); 
            }
        } else {
            duty -= 1000;
            if (duty == 0) {
                duty = 0;
                direction = 1; 
                delay(100000); 
            }
        }
        
        delay(15000); 
    }

    return 0;
}
