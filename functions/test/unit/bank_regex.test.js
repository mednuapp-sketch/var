const acc=/^\d{6,20}$/, ifsc=/^[A-Z]{4}0[A-Z0-9]{6}$/;
const t=(n,r,i,e)=>{const g=r.test(i);console.log(g===e?'ok  ':'FAIL',n,JSON.stringify(i));if(g!==e)process.exitCode=1};
['123456','12345678901234567890','12345','123456789012345678901','12ab56','',' 123456'].forEach((v,i)=>t('acc',acc,v,[true,true,false,false,false,false,false][i]));
['HDFC0001234','SBIN0ABC123','hdfc0001234','HDFC1001234','HDF0001234','HDFC00012345','ICIC0000001'].forEach((v,i)=>t('ifsc',ifsc,v,[true,true,false,false,false,false,true][i]));
