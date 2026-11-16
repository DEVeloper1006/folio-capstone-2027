/**
 * Paint the stored theme before the first stylesheet applies. Contains the inline script the document shell runs in the head. Keep its allowlist aligned with the palette ids and color modes in theme.ts.
 *
 * @file
 */

/** Apply folio-palette and folio-color-mode from localStorage onto the document element. */
export const themeBootScript = `(function(){try{var palette=localStorage.getItem('folio-palette');var mode=localStorage.getItem('folio-color-mode');var palettes={ink:1,forest:1,dusk:1,paper:1,chalk:1,harbor:1,margin:1};if(palettes[palette])document.documentElement.dataset.palette=palette;if(mode==='light'||mode==='dark')document.documentElement.dataset.colorMode=mode;}catch(e){}})();`
