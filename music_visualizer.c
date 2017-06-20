#include <stdio.h>
#include <stdlib.h>		// exit
#include <unistd.h>		// read
#include <sys/stat.h>	// open	
#include <fcntl.h>		// open
#include <stdint.h>		// uint16_t
#include "fft.h"		// fast fourier transform
#include "utils_curses.h"
#include "time.h"

#define MPD_FIFO "/tmp/mpd.fifo"
/*FREQ		44100*/
#define N_SAMPLES 	512
/*FPS		FREQ/N_SAMPLES*/

int
main(int argc, char *argv[])
{
	int fifo, i, j;
	WINDOW *mainwin;
	int maxR, maxC, avgLen, correction; //curses
	uint16_t buf[N_SAMPLES];
	unsigned int *fftBuf, *fftAvg;

	while((fifo = open(MPD_FIFO, O_RDONLY)) == -1);

	if (argc != 2){
		fprintf(stderr, "Usage: mvc [color number]\n");
		exit(EXIT_FAILURE);
	}


	if((mainwin = curses_init()) == NULL){
		exit(EXIT_FAILURE);
	}
	getmaxyx(stdscr, maxR, maxC);
	curs_set(0);
 	cbreak();
	nodelay(stdscr, TRUE);

	while(read(fifo, (uint16_t*)buf, 2*N_SAMPLES) != 0){
		/*usleep(45000);*/
		if(wgetch(stdscr)=='q'){
			break;
		}

		fftBuf = fast_fft(N_SAMPLES, (uint16_t*)buf);
		fftAvg = average_signal(fftBuf, N_SAMPLES, maxC, &avgLen);	
		free(fftBuf);

		erase();
		correction = 0;
		for(i=correction; i<maxC; i=i+1){
			color_set(atoi(argv[1]), NULL);
			for(j=0; j<1; j++){
				if(fftAvg[i] > maxR || fftAvg[i] < 0){
					fftAvg[i] = 1;
				}
				print_col(i+j-correction, fftAvg[i], maxR);
			}
		}
		refresh();
		free(fftAvg);
	}
	close(fifo);
	endwin();
	delwin(mainwin);

	return 0;
}
