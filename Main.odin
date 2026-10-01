package main

import "core:fmt"
import "core:sys/windows"
import "core:mem"
Running : bool

//Todo Global for now

win_offscreen_buffer :: struct {
	Info : windows.BITMAPINFO,
	Memory : rawptr,
	Width : i32,
	Height : i32,
	Pitch : i32,
	BytesPerPixel : i32
	
}


GlobalBuffer : win_offscreen_buffer

win_window_dimension :: struct {
	Width : i32,
	Height : i32,
}

GetWindowDimension :: proc "stdcall" (Window : windows.HWND) -> win_window_dimension{
	Result : win_window_dimension

	ClientRect : windows.RECT
	windows.GetClientRect(Window,&ClientRect)
	Result.Width = ClientRect.right - ClientRect.left
	Result.Height = ClientRect.bottom - ClientRect.top

	return Result
}


@(private="file")
RenderWeirdGradient :: proc "stdcall" (Buffer : ^win_offscreen_buffer, XOffset : i32, YOffset : i32) {

	
	Buffer.Pitch = Buffer.Width * Buffer.BytesPerPixel


	//casting from rawptr to char pointer
	//leaving this comment here to make myself remember the odin syntax
	Row : ^u8 = cast (^u8) Buffer.Memory
		
	for Y : i32= 0; Y < Buffer.Height; Y+=1 {
		//I'm so not sure about this
		//I'm trying to cast the Row PTR to a u32 PTR
		//I'm casting it first and then taking the pointer of it and THEN dereferencing with ^?
		Pixel : ^u32 = &(cast(^u32) Row)^
			
		for X: i32 = 0; X< Buffer.Width; X+=1 {
			Blue : u8 =cast(u8) (X + XOffset)
			Green : u8 =cast(u8) (Y + YOffset)
			Pixel^ = cast(u32) (cast(u32)Green <<8) | cast(u32) Blue
			//ptr offset takes the size of the ptr being passed into it
			//I thought I should pass 4 into it, but 1 works here
			//just like ptr++; in C that would move the pointer 4 bytes if it was an int
			
			Pixel = mem.ptr_offset(Pixel,1)
		}
		Row = mem.ptr_offset(Row,Buffer.Pitch)
	}
}

@(private="file")
ResizeDIBSection :: proc "stdcall" (Buffer : ^win_offscreen_buffer, Width: i32, Height: i32){
	//Todo: Bulletproof this
	//Maybe don't free first, free after, then free first if that fails
	if Buffer.Memory != nil {
		windows.VirtualFree(Buffer.Memory, 0, windows.MEM_RELEASE)
	}
	Buffer.Width = Width
	Buffer.Height = Height
	Buffer.BytesPerPixel = 4

	Buffer.Info.bmiHeader.biSize = size_of(Buffer.Info.bmiHeader)
	Buffer.Info.bmiHeader.biWidth = Buffer.Width
	Buffer.Info.bmiHeader.biHeight = -Buffer.Height
	Buffer.Info.bmiHeader.biPlanes = 1
	Buffer.Info.bmiHeader.biBitCount = 32
	Buffer.Info.bmiHeader.biCompression = windows.BI_RGB
	Buffer.Info.bmiHeader.biSizeImage = 0
	Buffer.Info.bmiHeader.biXPelsPerMeter = 0
	Buffer.Info.bmiHeader.biYPelsPerMeter = 0
	Buffer.Info.bmiHeader.biClrImportant = 0

	BitmapMemorySize : i32 =  (Width* Height)*Buffer.BytesPerPixel
	Buffer.Memory = windows.VirtualAlloc(nil, uint (BitmapMemorySize),windows.MEM_COMMIT,windows.PAGE_READWRITE)

	RenderWeirdGradient(Buffer,128,0)

}
@(private="file")
DisplayBufferToWindow :: proc "stdcall"(DeviceContext : windows.HDC,
										WindowWidth : i32,
										WindowHeight : i32,
										Buffer : ^win_offscreen_buffer,
										X : i32,
										Y : i32,
										Width: i32,
										Height: i32) {
	//Todo : Aspect Ratio Correction
	
	windows.StretchDIBits(DeviceContext,
						  //X,
						  //Y,
						  //Width,
						  //Height,
						  //X,
						  //Y,
						  //Width,
						  //Height,
						  0,0, WindowWidth,WindowHeight,
						  0,0, Buffer.Width,Buffer.Height,
						  Buffer.Memory,
						  &Buffer.Info,
						  windows.DIB_RGB_COLORS,
						  windows.SRCCOPY)
}


MainWindowCallback :: proc "stdcall"(WindowHandle : windows.HWND ,
									 Message: u32,
									 WPARAM: uintptr ,
									 LPARAM: int ) -> int {
	
	Result : windows.LRESULT = 0
	
	switch Message {
	case windows.WM_SIZE : {//Create a buffer and draw a buffer
	}
	case windows.WM_DESTROY : {
		//Todo: Handle this as an error - recreate window?
		Running = false
	}
	case windows.WM_CLOSE : {
		//Todo: Handle this with a message to the user
		Running = false
	}
	case windows.WM_ACTIVATEAPP : {
		windows.OutputDebugStringA("WM_ActivateApp")		
	}
	case windows.WM_PAINT: {
		Paint : windows.PAINTSTRUCT
		//HDC
		DeviceContext := windows.BeginPaint(WindowHandle, &Paint)
		
		X : i32 = Paint.rcPaint.left
		Y : i32 = Paint.rcPaint.top
		Dimension := GetWindowDimension(WindowHandle)
		DisplayBufferToWindow(DeviceContext,Dimension.Width,Dimension.Height,&GlobalBuffer,
							  X,Y,Dimension.Width,Dimension.Height)
		
		windows.EndPaint(WindowHandle, &Paint)
	}
	case :{
		//		windows.OutputDebugStringA("default")
		Result = windows.DefWindowProcA(WindowHandle,Message,WPARAM,LPARAM)
	}
	}
	return Result
}

main :: proc(){
	wnd : windows.WNDCLASSW
 

	ResizeDIBSection(&GlobalBuffer,1280,720)

	wnd.style = windows.CS_HREDRAW | windows.CS_VREDRAW
	wnd.lpfnWndProc = MainWindowCallback
	wnd.hInstance = windows.HINSTANCE( windows.GetModuleHandleW(""))
	//	wnd.hIcon = ;
	wnd.lpszClassName = "OdinEngine"

	//Returns an Atom but I don't care
	if windows.RegisterClassW(&wnd) != 0 {
		WindowHandle := windows.CreateWindowExW (
			0, 
			wnd.lpszClassName,
			"OdinEngine",
			windows.WS_OVERLAPPEDWINDOW | windows.WS_VISIBLE, 
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			nil,
			nil,
			wnd.hInstance,
			nil)
		if WindowHandle != nil {
			Running = true
			XOffset : i32 = 0
			YOffset : i32 = 0
			//it seems there's no while loop in odin
			//it's all for loop, and I've dropped the increment step and the initial step
			for ; Running; {

				Message : windows.MSG
				//This is wrong
				//for MessageResult == false  {
				//This works which I think it means it's returning a bool?
				//it's returning a BOOL which is coming from windows, but can I if it easily?
				//this is such a weird issue that I have, if I use the version below it works flawlessly
				//for windows.PeekMessageW(&Message,nil,0,0, windows.PM_REMOVE) {
				//but if use the one below it doesn't work at all
				//I have no clue what's going on, I just use the one that works
				//for MessageResult == windows.FALSE{
				for windows.PeekMessageW(&Message,nil,0,0, windows.PM_REMOVE) {
					if Message.message == windows.WM_QUIT {
						Running = false
					}
					windows.TranslateMessage(&Message)
					windows.DispatchMessageW(&Message)
				}
				RenderWeirdGradient(&GlobalBuffer,XOffset,YOffset)
				
				{
					DeviceContext : windows.HDC = windows.GetDC(WindowHandle )
					Dimension := GetWindowDimension(WindowHandle)
					DisplayBufferToWindow(DeviceContext,Dimension.Width, Dimension.Height,
										  &GlobalBuffer,0,0,Dimension.Width,Dimension.Height)
					windows.ReleaseDC(WindowHandle,DeviceContext)
				}
				
				XOffset +=1
				YOffset +=2
			}
			
		}
		else {
			//Todo: Window Handle Failed, Logging
		}
	}
	else {
		//Todo: register window class failed, Logging
	}
		
	return
}
