//=================================================================================================
//
//	SerialDrv.h		This is a nice C++ class to wrap up a COM port up so I don't have to worry
//					about blocks and buffers in the main code,
//					Its main function is to grab stuff off the line and present it to the
//					caller in nice lines that were "text text text\r" but we strip the \n
//
//					code by Nigel Hewitt from the late 1990s but with tweaks
//
//=================================================================================================

class SERIAL {
	public:
		SERIAL(LPCSTR name, int baud);					// the constructor takes port name and baud rate and then opens
		~SERIAL();

		bool		open(LPCSTR name, int baud);
		bool		reopen(){ return open(szPortName, nBaud); }
		bool		close();
		bool		ok(){ return _ok; }
		const char*	port(){ return szPortName; }
		int			baud(){ return nBaud; }
		DWORD		error();							// return windows error stuff
		bool		send(LPCSTR s, size_t cb=0);		// send data a block of stuff, if it is null terminated leave off cb
		bool		send(char c);						// send a single character
		int			getc();								// get a single character (or -1)
		bool		gets(char*, size_t cb);				// get a string that did have a \r at the end
		int			get(char*, size_t cb);				// get anything (even nulls)
		void		flush(){ iBuffer = nBuffer = 0; }
		void		logging(bool on, bool newfile);		// log on/off
		void		setlog(const char* log);
		void		record(const char *str);
		void		check();							// check if failed and reopen

		bool		getDTR(){ return dtr; }
		bool		getRTS(){ return rts; }
		void		setDTR(bool val);
		void		setRTS(bool val);

	private:
		int		read(LPSTR buffer, size_t cbBuffer);	// read data
		int		write(LPCSTR buffer, size_t cbBuffer);	// write data
		bool	poll();									// poll the receiver

		char	szPortName[20]{};						// port name
		int		nBaud;
		DCB		dcb;
		HANDLE	handle;
		bool	_ok {false};
		DWORD	err;
		char	buffer[1024];							// recirculating received data buffer
		size_t	iBuffer;								// iBuffer is index of next character
		size_t	nBuffer;								// number of bytes in the buffer
		bool	dtr{}, rts{};							// initially unset
		HANDLE	logFile{};
		char	szLogFile[MAX_PATH] {};
		bool	read_mode;
		int		counter;
		void	read_log(char* bx, size_t cb);			// diagnostic port logging
		void	write_log(const char* bx, size_t cb);
		void	expand(const char* bx, size_t cb);
		DWORD	WriteFile(HANDLE h, LPCSTR s){ DWORD n; ::WriteFile(h, s, lstrlen(s), &n, 0); return n; }
};
