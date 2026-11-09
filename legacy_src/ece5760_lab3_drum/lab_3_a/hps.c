///////////////////////////////////////
/// 640x480 version! 16-bit color
/// This code will segfault the original
/// DE1 computer
/// compile with
/// gcc hps.c -o hps_lab3 -O2 -lm -pthread
///
///////////////////////////////////////
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/ipc.h> 
#include <sys/shm.h> 
#include <sys/mman.h>
#include <sys/time.h> 
#include <math.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdbool.h>
//#include "address_map_arm_brl4.h"

// video display
#define SDRAM_BASE            0xC0000000
#define SDRAM_END             0xC3FFFFFF
#define SDRAM_SPAN			  0x04000000
// characters
#define FPGA_CHAR_BASE        0xC9000000 
#define FPGA_CHAR_END         0xC9001FFF
#define FPGA_CHAR_SPAN        0x00002000
/* Cyclone V FPGA devices */
#define HW_REGS_BASE          0xff200000
//#define HW_REGS_SPAN        0x00200000 
#define HW_REGS_SPAN          0x00005000 

// === the fixed point macros (1.17) ========================================
typedef signed int fix17;
#define int2fix(a) ((fix17)((a) << 17))
#define fix2int(a) ((int)((a) >> 17))

#define float2fix(a) ((fix17)((a) * 131072.0))
#define fix2float(a) ((float)(a) / 131072.0)

//define pio offset
#define PIO0_OFFSET 0x00
#define PIO1_OFFSET 0x10
#define PIO2_OFFSET 0x20
#define PIO3_OFFSET 0x30
#define PIO4_OFFSET 0x40
#define PIO5_OFFSET 0x50
#define PIO6_OFFSET 0x60
#define PIO7_OFFSET 0x70

// graphics primitives
void VGA_text (int, int, char *);
void VGA_text_clear();
void VGA_box (int, int, int, int, short);
void VGA_rect (int, int, int, int, short);
void VGA_line(int, int, int, int, short) ;
void VGA_Vline(int, int, int, short) ;
void VGA_Hline(int, int, int, short) ;
void VGA_disc (int, int, int, short);
void VGA_circle (int, int, int, int);
// 16-bit primary colors
#define red  (0+(0<<5)+(31<<11))
#define dark_red (0+(0<<5)+(15<<11))
#define green (0+(63<<5)+(0<<11))
#define dark_green (0+(31<<5)+(0<<11))
#define blue (31+(0<<5)+(0<<11))
#define dark_blue (15+(0<<5)+(0<<11))
#define yellow (0+(63<<5)+(31<<11))
#define cyan (31+(63<<5)+(0<<11))
#define magenta (31+(0<<5)+(31<<11))
#define black (0x0000)
#define gray (15+(31<<5)+(51<<11))
#define white (0xffff)
int colors[] = {red, dark_red, green, dark_green, blue, dark_blue, 
		yellow, cyan, magenta, gray, black, white};

// pixel macro
#define VGA_PIXEL(x,y,color) do{\
	int  *pixel_ptr ;\
	pixel_ptr = (int*)((char *)vga_pixel_ptr + (((y)*640+(x))<<1)) ; \
	*(short *)pixel_ptr = (color);\
} while(0)

// the light weight buss base
void *h2p_lw_virtual_base;

// pixel buffer
volatile unsigned int * vga_pixel_ptr = NULL ;
void *vga_pixel_virtual_base;

// character buffer
volatile unsigned int * vga_char_ptr = NULL ;
void *vga_char_virtual_base;

// /dev/mem file id
int fd;

// measure time
struct timeval t1, t2;
double elapsedTime;



signed int * pio0_test; // number of rows
signed int * pio1_test; // rho gain | initial rho
signed int * pio2_test; // init amplitude
signed int * pio3_test;  // reset
signed int * pio4_test;  // incr_value_row = inital amplitude / (num_of_col/2)
signed int * pio5_test;  // incr_value_col = inital amplitude / (num_of_col/2) / (num_of_row/2)
signed int * pio6_test;  // inital eta
signed int * pio7_test;  // finished

int first = 0;

void *read0() { 

//     while(*pio7_test == 0) {
//         printf("first 0!\n");
//     }
//     gettimeofday(&t1, NULL);
//     while(*pio7_test == 1) {
//         printf("first 1!\n");
//     }

//     while(*pio7_test == 0) {
//         printf("second 0!\n");
//     }
    

//     while(*pio7_test == 1) {
//         printf("second 1!\n");
//     }
//     gettimeofday(&t2, NULL);
//     printf("finished !\n");
//     elapsedTime = (t2.tv_sec - t1.tv_sec) * 1000000.0;
//     printf("elapsed time(us) %f \n", elapsedTime); 
}

void *draw() {
    char str1;
    int updated;
    updated = 0;

    int str_number_of_row;
    str_number_of_row = 151;


    int initial_reset;
    initial_reset = 0;

    float col_incr;
    col_incr = 0.25/225;
    float row_incr;
    row_incr = 0.25/15;

    const int str_number_of_col = 151;

    float rho;
    rho = 0.25;

    float initial_amplitude;
    initial_amplitude = 0.25;
    
    float eta;
    eta = 0;



    while(1) {
		printf("Enter Command ('0' -> number of rows, '1' -> rho gain, '2' -> inital amplitude, '3' -> reset, '4 -> intial eta:   \n");
		scanf("%c", &str1);
        updated = 0;
		if (str1 == '0') {
			printf("Enter new number of rows as an integer: ");
			scanf("%d", &str_number_of_row);
            *pio0_test = str_number_of_row;
            updated = 1;
		} else if (str1 == '1') {
			printf("Enter value of the exponential for new rho gain: ");
			scanf("%f", &rho); 
            updated = 1;
            *pio1_test = float2fix(rho);
		} else if (str1 == '2') {
            printf("Enter new initial amplitude: ");
			scanf("%f", &initial_amplitude);
            updated = 1;
            *pio2_test = float2fix(initial_amplitude);
            *pio4_test = float2fix(initial_amplitude/ (str_number_of_col/2));
            *pio5_test = float2fix(initial_amplitude/ (str_number_of_col/2)/(str_number_of_row/2));
        } else if (str1 == '3') {
            updated = 1;
            *pio3_test = updated;
        } else if (str1 == '4') {
            printf("Enter initial eta value: ");
			scanf("%f", &eta);
            *pio6_test = float2fix(eta);
        } else {
            updated = 0;
        }
        
        *pio3_test = updated;
    }
}

int main(void)
{   
    pthread_t thread_read,thread_draw;
    pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

    // measure time
    struct timespec delay_time ;
    delay_time.tv_nsec = 10 ;
    delay_time.tv_sec = 0 ;

     // Open /dev/mem
	if( ( fd = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) 	{
		printf( "ERROR: could not open \"/dev/mem\"...\n" );
		return( 1 );
	}
    
    // get virtual addr that maps to physical
	h2p_lw_virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ), MAP_SHARED, fd, HW_REGS_BASE );	
	if( h2p_lw_virtual_base == MAP_FAILED ) {
		printf( "ERROR: mmap1() failed...\n" );
		close( fd );
		return(1);
	}
    
	pio0_test =(signed int *)(h2p_lw_virtual_base+PIO0_OFFSET);
	pio1_test =(signed int *)(h2p_lw_virtual_base+PIO1_OFFSET);
	pio2_test =(signed int *)(h2p_lw_virtual_base+PIO2_OFFSET);
    pio3_test =(signed int *)(h2p_lw_virtual_base+PIO3_OFFSET);
	pio4_test =(signed int *)(h2p_lw_virtual_base+PIO4_OFFSET);
	pio5_test =(signed int *)(h2p_lw_virtual_base+PIO5_OFFSET);
	pio6_test =(signed int *)(h2p_lw_virtual_base+PIO6_OFFSET);
	pio7_test =(signed int *)(h2p_lw_virtual_base+PIO7_OFFSET);

    pthread_create(&thread_read,NULL,read0,NULL);
    pthread_create(&thread_draw,NULL,draw,NULL);

    
    pthread_join(thread_read,NULL);
    pthread_join(thread_draw,NULL);
    return 0;
} // end main


