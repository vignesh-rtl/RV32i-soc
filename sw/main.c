int main()
{
    volatile int a = 5;
    volatile int b = 7;
    volatile int c;

    c = a + b;

    while(1);
}
