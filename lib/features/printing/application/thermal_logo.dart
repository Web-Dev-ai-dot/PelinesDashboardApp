// Monochrome raster from assets/branding/pelines_logo.png.
// Cropped to the alpha bounds, composited on white, resized with Lanczos
// and packed MSB-first, with one bit per black dot (threshold 150).
const thermalLogoWidthBytes = 20;
const thermalLogoHeight = 89;
const thermalLogoBase64 =
    'AAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAPwAAAAAAHAAAAAAAAAAAAAAAAAB/wAAAAAA+A'
    'AAAAAAAAAAAAAAAAH/wAAAAAHwAAAAAAAAAAAAAAAAAf/wAAAAA+AAAAAAAAAAAAAAAAAAf/'
    'gAAAAHwAAA/wAAAAAAAAAAAAAP/AAAAAeAAA//AAAAAAAAAAAAAAH+BgACDwAAf/8AAAAAAA'
    'AAAAAAAH8HAAYeAAH//wAAAAAAAAAAAAAAP4+ADz4AB//wAAAAAAAAAAAAAAAPz8YfPAAP/g'
    'AAAAAAAAAAA8AAAAf/7z/4AD/wAAAAAAAAAAB//wAAA/////AAf8AAAAAAAAAAAf//wAAD//'
    '//8AD/AAAAAAAAAAAB///4Dgf////8A/wAAA//8AAAAAH///4P5/////wH8AAA///+AAAAAf'
    '///w///////gfgAAf///+AAAABgAf/z////+f+/8AAH////+AAAAAAAH/////35///AAB//w'
    'B/4AAAAAAAD///7+PH//8AAf/gAAPgAAAAAAAD///nwYd//wAH/wAAAMAAAAAAAAH//8eAD3'
    '//AA/4AAAAAAAAAAAAAP/Dw8AOf/8AH+AAAAAAAAAAAAAAf8ABwA59/wB/gAAAAAAAAAAAAA'
    'B/wAHgHiP/wP4AAAAAAAAA//4AAP/AAOAcA//x+AAAAAAAAAf//+AH/+AA4BwH//PwAAAAAA'
    'AAP///+Af/8ABwHAf/9+AAAABAAAD////+B//4AHA4Dz//gAAf/+AAAf/AAf+H//gAeDgOB/'
    '+P///4YAAH/gAAP8/4PAA4OB4f///+AABgAA/wAAAH//AeADg7////AAAADEAAH+AAAAH/8A'
    '4B////wAAAB//8QAA/gAAAAf/7////4AAAB/////zAAH4AAAAH////8AAAA////////MAAfA'
    'AAD///+AAAAf/////////8wAA4Af///AAAAf////////////yAABAf/wAAAP////////////'
    '//+YAAADAAAH/////////////////5gAAAEH/////////////////D//mAAAAb//8H//////'
    '///////gB/+YAADxn/+AH////////////8AB/5AAAfmf/gAP4f4P/Pg//gB/gAD/M4AD+Z/4'
    'AAfADg/w+D8MAH8AAP8z+AP8n/AMB8AGD/D4HxwAfwPh/zP4A/if4D4HwAYP8HgeHB//A/n/'
    'M/AD+N/gfwfDxg/weA4cP/8D//8j8AHwz/A/B8P+D/B4Dhw//wH//mfwAADP8D8Hg/4P8HgG'
    'HD//gP/+Z+AAGM/4HgeB/g/4eIYcAH+AP/5n4AD8T/gcD4AeH/hwwhwAf8Af/mfgAHxv/Agf'
    'gA4f+HDCHAB/4A/+R+AAfGf8AD+AHh/4cOAcH//4B/zHwAB8Z/4Af4feH/hw4Bwf//wD/M/A'
    'AH5n/gH/B/4f+HDwHB///gP8z8AAfif/A/8P/h/4MPAcH///A/zPgAB+J/8D/wf+ADgw+B4A'
    'Hn8D+I+AAH43/4H/AD4AODD4HgAcPwP5j4AAfjP/gf8AHgA4MPweABgAA/mPgAA/M//A/+Ae'
    'ADw4/B4B+AAH+YAAAD8z/8D//5/////////8AA/5DgAAPxP/4H////////////8AH/EfAAA/'
    'G//g/////////////+D/8z+AAD+Z//P////////////////zP4AAP5n/////////////////'
    '//M/gAA/mf//////////////////8j+AABgJ///////////////////iHwAAAAgAAAAAAAB/'
    '/////////+YOAAAADAAAAAAAAAAAAAAAAAAAxgAAAAAP/////////////////AAGAAAAAAAP'
    '//////////////////wAAAAAAB///////////////////AAAAAAAH/////////////////+A'
    'AAAAAAA//BBhgEePz85hhhjH/4AAAAAAAD/9U02Wb4+PxGVs2O//wAAAAAAAf/9x3Jbvj4vQ'
    'Y8347//AAAAAAAB//3Pclu0PJ9Nnndjt/8AAAAAAAD/+ckmWSScnymUEkkH/wAAAAAAAP/5w'
    '485DZ5veYY8yY/+AAAAAAAAf///7/////////////4AAAAAAAB//////////////////AAAA'
    'AAAAB/////////////////4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';
