#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
 if (argc != 4) return 2;
 void *h = dlopen(argv[1], RTLD_NOW|RTLD_LOCAL); if(!h) {fprintf(stderr,"%s\n",dlerror()); return 1;}
 int (*init)(const char *)=dlsym(h,"vips_init"); void *(*load)(const char *,...)=dlsym(h,"vips_image_new_from_file");
 int (*write)(void *,const char *,...)=dlsym(h,"vips_image_write_to_file"); const char *(*error)(void)=dlsym(h,"vips_error_buffer"); void (*unref)(void *)=dlsym(h,"g_object_unref");
 if(!init || !load || !write || !error || !unref || init(argv[0])) return 3;
 void *img=load(argv[2],NULL); if(!img){fprintf(stderr,"%s\n",error());return 4;}
 int (*width)(void *)=dlsym(h,"vips_image_get_width"); int (*height)(void *)=dlsym(h,"vips_image_get_height");
 if (!width || !height || width(img) <= 0 || height(img) <= 0 || (long long)width(img)*height(img) > 100000000LL) { fprintf(stderr,"Image dimensions exceed 100 megapixels or are invalid\n"); unref(img); return 6; }
 int result=write(img,argv[3],NULL); if(result)fprintf(stderr,"%s\n",error()); unref(img); return result ? 5 : 0;
}
